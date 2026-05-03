import Foundation

/// Decides whether and when to auto-reply, and supports burst-batching when
/// senders break their thoughts into multiple back-to-back messages.
@MainActor
final class SmartTriggers {
    /// Tunables
    var graceWindowSeconds: TimeInterval = 8
    var maxBurstWindowSeconds: TimeInterval = 30
    var quietHoursStart: Int = 23  // 11pm
    var quietHoursEnd: Int = 7     // 7am
    var quietHoursEnabled: Bool = false

    private let dbService: ChatDatabaseService
    private let ollama: OllamaService

    /// Pending reply tasks per contact (id-keyed). When a new message arrives
    /// for the same contact, we cancel + reschedule to batch the burst.
    private var pendingByContact: [String: PendingReply] = [:]

    struct PendingReply {
        var firstArrivedAt: Date
        var latestMessage: ChatMessage
        var allMessages: [ChatMessage]
        var task: Task<Void, Never>
    }

    enum Decision {
        case skip(reason: String)
        case fire(merged: [ChatMessage])
    }

    init(dbService: ChatDatabaseService, ollama: OllamaService) {
        self.dbService = dbService
        self.ollama = ollama
    }

    // MARK: - Heuristic gates (cheap, deterministic)

    /// Returns nil if message is "definitely worth replying to",
    /// a string if we should skip with a reason,
    /// or .borderline if we should let the LLM decide.
    enum HeuristicResult {
        case reply
        case skip(String)
        case borderline
    }

    func heuristicGate(_ msg: ChatMessage) -> HeuristicResult {
        let text = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty or attachment-only
        if text.isEmpty {
            return msg.hasAttachment ? .reply : .skip("empty message")
        }

        let lower = text.lowercased()

        // GREETINGS — always reply, even if very short (gm, gn, hey, yo, sup)
        let greetings: Set<String> = [
            "gm", "g.m", "g.m.", "good morning", "morning", "mornin", "mornin'",
            "gn", "g.n", "good night", "goodnight", "night", "nighty",
            "hey", "heyy", "heyyy", "hey there", "hi", "hii", "hello", "helo", "henlo",
            "yo", "yoo", "yooo", "ayo", "ay", "wassup", "whats up", "what's up", "sup",
            "wyd", "what u doing", "what you doing", "wya", "where you at", "where u at",
            "u up", "you up", "u there", "you there"
        ]
        if greetings.contains(lower) { return .reply }

        // Common acknowledgments — these we skip
        let ackWords: Set<String> = [
            "ok", "kk", "k", "okay", "k.", "ok.", "kk.",
            "lol", "lmao", "rofl", "haha", "hehe", "ha", "hahaha", "lolol",
            "cool", "nice", "sweet", "awesome", "great", "perfect",
            "thx", "ty", "tysm", "thanks", "thank you", "thanku",
            "yes", "yep", "yup", "ya", "yeah", "sure",
            "no", "nope", "nah",
            "hmm", "mhm", "mhmm",
            "got it", "noted", "sounds good", "alright", "aight", "word", "bet", "ight"
        ]
        if ackWords.contains(lower) { return .skip("ack/short reply") }

        // Single character / very short non-greeting non-ack
        if text.count <= 1 { return .skip("too short (\(text.count) chars)") }

        // Pure emoji message (no letters/digits)
        let hasAlphanumeric = text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        if !hasAlphanumeric { return .skip("emoji/punctuation only") }

        // Question or planning → reply
        if text.contains("?") { return .reply }
        let planKeywords = ["when", "where", "what time", "let me know", "wyd", "u free", "you free", "you up", "u up", "down to", "wanna"]
        if planKeywords.contains(where: lower.contains) { return .reply }

        // Status updates / short content messages with letters → reply
        // ("blazing", "im up", "at the gym", "starving", "bored", etc.)
        // Anything that's a real word and not a pure ack is worth at least the LLM check
        if text.count >= 3 && hasAlphanumeric { return .reply }

        return .borderline
    }

    /// Borderline cases: ask Ollama "does this need a reply? yes/no"
    func llmBorderlineGate(_ msg: ChatMessage) async -> Bool {
        let prompt = """
        You are filtering text messages to decide which ones genuinely need a reply.
        Reply with ONLY one word: YES or NO.

        Reply YES if the message:
        - Asks a question
        - Suggests plans, makes an invitation, asks for confirmation
        - Shares news that warrants a response
        - Is open-ended and a reply would be expected

        Reply NO if the message:
        - Is just an acknowledgment, reaction, or filler ("haha", "ok", "thanks", "lol")
        - Closes a thread without inviting more
        - Is a single thought that doesn't need follow-up

        Message: "\(msg.text)"

        Reply (YES or NO only):
        """

        let response = (try? await ollama.generate(prompt: prompt)) ?? ""
        let normalized = response.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Be conservative: only count exact YES as "yes". Any other answer → skip.
        return normalized == "YES" || normalized.hasPrefix("YES")
    }

    // MARK: - Quiet hours / focus checks

    func inQuietHours() -> Bool {
        guard quietHoursEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        if quietHoursStart < quietHoursEnd {
            return hour >= quietHoursStart && hour < quietHoursEnd
        } else {
            // Wraps midnight (e.g. 23 → 7)
            return hour >= quietHoursStart || hour < quietHoursEnd
        }
    }

    /// True if the user has manually replied to this contact within the given window.
    func userRepliedRecently(toAnyHandleOf contact: Contact, since: Date) -> Bool {
        guard let history = try? dbService.fetchUnifiedHistory(forHandles: contact.handles, limit: 5) else {
            return false
        }
        return history.contains { $0.isFromMe && $0.date > since }
    }

    // MARK: - Burst-aware grace window

    /// Schedule a reply with a grace window. If another message from the same
    /// contact arrives during the window, the existing task is cancelled and a
    /// new one is scheduled, batching all messages together.
    /// Returns the merged set of messages when the window finally elapses.
    func scheduleWithGraceWindow(
        contact: Contact,
        incoming: ChatMessage,
        onFire: @escaping ([ChatMessage]) async -> Void,
        onSkip: @escaping (String) -> Void
    ) {
        // Cancel any existing pending task for this contact and merge messages
        var allMessages: [ChatMessage] = [incoming]
        var firstArrivedAt = Date()
        if let existing = pendingByContact[contact.id] {
            existing.task.cancel()
            allMessages = existing.allMessages + [incoming]
            firstArrivedAt = existing.firstArrivedAt
        }

        // Clamp: if the burst has been going on for >maxBurstWindowSeconds, fire now anyway
        let burstAge = Date().timeIntervalSince(firstArrivedAt)
        let waitTime = min(graceWindowSeconds, max(1.0, maxBurstWindowSeconds - burstAge))

        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self else { return }

            // Final check: did the user reply manually during the window?
            if self.userRepliedRecently(toAnyHandleOf: contact, since: firstArrivedAt) {
                self.pendingByContact.removeValue(forKey: contact.id)
                onSkip("user replied first")
                return
            }

            self.pendingByContact.removeValue(forKey: contact.id)
            await onFire(allMessages)
        }

        pendingByContact[contact.id] = PendingReply(
            firstArrivedAt: firstArrivedAt,
            latestMessage: incoming,
            allMessages: allMessages,
            task: task
        )
    }

    func cancel(contactID: String) {
        if let pending = pendingByContact[contactID] {
            pending.task.cancel()
            pendingByContact.removeValue(forKey: contactID)
        }
    }

    func cancelAll() {
        for (_, p) in pendingByContact { p.task.cancel() }
        pendingByContact.removeAll()
    }

    var pendingCount: Int { pendingByContact.count }
}
