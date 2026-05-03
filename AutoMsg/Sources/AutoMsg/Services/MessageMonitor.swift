import Foundation
import Combine

@MainActor
final class MessageMonitor: ObservableObject {
    @Published var isRunning = false
    @Published var pendingAutoReplies: Int = 0

    private let dbService: ChatDatabaseService
    private let ollama: OllamaService
    private let sender: MessageSender
    private var timer: Timer?
    private var lastProcessedROWID: Int64
    private var lastReplyTime: [String: Date] = [:]
    private let minReplyInterval: TimeInterval = 5
    private var isProcessing = false

    let smartTriggers: SmartTriggers
    let memorySummarizer: MemorySummarizer
    /// Memory updater callback — called after memory is refreshed for a contact (id, new memory)
    var onMemoryUpdated: ((String, ContactMemory) -> Void)?
    var onAutoReplySent: ((String, String, String) -> Void)?
    var onAutoReplySkipped: ((String, String) -> Void)?
    var onDraftGenerated: ((String, String) -> Void)?
    var onError: ((String) -> Void)?

    init(dbService: ChatDatabaseService, ollama: OllamaService, sender: MessageSender) {
        self.dbService = dbService
        self.ollama = ollama
        self.sender = sender
        self.lastProcessedROWID = Persistence.lastProcessedROWID
        self.smartTriggers = SmartTriggers(dbService: dbService, ollama: ollama)
        self.memorySummarizer = MemorySummarizer(dbService: dbService, ollama: ollama)
        self.intentClassifier = IntentClassifier(ollama: ollama)
    }

    let intentClassifier: IntentClassifier

    /// Callback fired when an auto-reply abstains and we want the user to draft manually.
    var onAbstainedToDraft: ((String, String, String) -> Void)?  // (contactID, reason, suggestedDraft?)

    func start(contacts: [Contact]) {
        guard !isRunning else { return }

        if lastProcessedROWID == 0 {
            lastProcessedROWID = (try? dbService.getMaxROWID()) ?? 0
            Persistence.lastProcessedROWID = lastProcessedROWID
        }

        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.poll(contacts: contacts)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func restart(contacts: [Contact]) {
        stop()
        start(contacts: contacts)
    }

    private func poll(contacts: [Contact]) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let enabledContacts = contacts.filter { $0.isEnabled && $0.smartMode != .off && $0.smartMode != .draftOnly }
        guard !enabledContacts.isEmpty else { return }

        do {
            let newMessages = try dbService.fetchNewMessages(afterROWID: lastProcessedROWID)

            for message in newMessages {
                lastProcessedROWID = max(lastProcessedROWID, message.id)
                Persistence.lastProcessedROWID = lastProcessedROWID

                guard let matched = enabledContacts.first(where: { $0.matches(handle: message.contactID) }) else {
                    continue
                }

                let cutoff = Date().addingTimeInterval(-120)
                guard message.date > cutoff else { continue }

                await routeMessage(message, contact: matched)
            }
        } catch {
            onError?("Poll error: \(error.localizedDescription)")
        }
    }

    /// Apply gates, then either fire immediately or schedule with grace window.
    private func routeMessage(_ message: ChatMessage, contact: Contact) async {
        // Rate-limit gate (always applies, even in alwaysAuto mode)
        if let lastReply = lastReplyTime[contact.id],
           Date().timeIntervalSince(lastReply) < minReplyInterval {
            return
        }

        // Mode-specific gating
        switch contact.smartMode {
        case .off, .draftOnly:
            return  // shouldn't reach here, but defensive

        case .alwaysAuto:
            // Bypass smart triggers — old behavior
            await handleIncomingMessage(message, contact: contact, mergedMessages: [message])
            return

        case .focusOnly:
            if !isFocusActive() {
                onAutoReplySkipped?(contact.id, "Focus not active")
                return
            }
            fallthrough  // also apply moderate gates

        case .moderate:
            // Quiet hours gate (per-contact, but we honor global setting too)
            if smartTriggers.inQuietHours() {
                onAutoReplySkipped?(contact.id, "quiet hours")
                return
            }

            // Heuristic gate
            switch smartTriggers.heuristicGate(message) {
            case .skip(let reason):
                onAutoReplySkipped?(contact.id, reason)
                return
            case .borderline:
                let needsReply = await smartTriggers.llmBorderlineGate(message)
                if !needsReply {
                    onAutoReplySkipped?(contact.id, "LLM judged not worth replying")
                    return
                }
            case .reply:
                break
            }

            // Burst-aware grace window: schedule and let it batch with subsequent messages
            smartTriggers.scheduleWithGraceWindow(
                contact: contact,
                incoming: message,
                onFire: { [weak self] mergedMessages in
                    guard let self else { return }
                    await self.handleIncomingMessage(message, contact: contact, mergedMessages: mergedMessages)
                    self.pendingAutoReplies = self.smartTriggers.pendingCount
                },
                onSkip: { [weak self] reason in
                    self?.onAutoReplySkipped?(contact.id, reason)
                    self?.pendingAutoReplies = self?.smartTriggers.pendingCount ?? 0
                }
            )
            pendingAutoReplies = smartTriggers.pendingCount
        }
    }

    private func isFocusActive() -> Bool {
        // macOS exposes Focus state via NSUserDefaults under com.apple.focus
        // and via the assertion API. Quickest path: check the do-not-disturb file.
        let path = "\(NSHomeDirectory())/Library/DoNotDisturb/DB/Assertions.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let assertions = json["data"] as? [[String: Any]],
           let first = assertions.first,
           let storeAssertions = first["storeAssertionRecords"] as? [[String: Any]] {
            return !storeAssertions.isEmpty
        }
        return false
    }

    var allowSMSReplies: Bool = false

    var unifiedHistoryProvider: ((String) -> [ChatMessage])?
    /// Lookup callback: given a contact id, return the most-recent Contact (with memory).
    var contactProvider: ((String) -> Contact?)?

    private func handleIncomingMessage(_ message: ChatMessage, contact: Contact, mergedMessages: [ChatMessage]) async {
        do {
            var liveContact = contactProvider?(contact.id) ?? contact
            if liveContact.memory.isEmpty {
                print("[Memory] Seeding initial memory for \(liveContact.displayLabel) before first reply")
                if let seeded = await memorySummarizer.refreshMemory(for: liveContact) {
                    onMemoryUpdated?(contact.id, seeded)
                    liveContact.memory = seeded
                }
            } else if liveContact.memory.styleProfile.isEmpty {
                if let style = memorySummarizer.refreshStyleOnly(for: liveContact) {
                    liveContact.memory.styleProfile = style
                    onMemoryUpdated?(contact.id, liveContact.memory)
                }
            }

            let unified = unifiedHistoryProvider?(contact.id) ?? []
            let history = unified.isEmpty
                ? (try dbService.fetchConversationHistory(chatIdentifier: message.chatIdentifier, limit: 20))
                : unified

            let memory = liveContact.memory.isEmpty ? nil : liveContact.memory

            // Classify the latest message's intent. The model uses this to pick the right posture.
            let latestText = mergedMessages.last?.text ?? message.text
            let intent = await intentClassifier.classify(message: latestText, recentContext: history)
            print("[Intent] \(contact.displayLabel): \(intent?.rawValue ?? "unknown")")

            // Hard short-circuit: if the classifier says only the user can answer, abstain immediately.
            if intent == .needsUser {
                print("[Abstain] \(contact.displayLabel): needs_user — routing to draft")
                onAbstainedToDraft?(contact.id, "Needs your input — answer manually", "")
                return
            }

            let prompt: String
            if mergedMessages.count > 1 {
                prompt = ConversationContext.buildAutoReplyPromptForBurst(
                    contact: contact.displayLabel,
                    newMessages: mergedMessages.map { $0.text },
                    history: history,
                    memory: memory,
                    intent: intent
                )
            } else {
                prompt = ConversationContext.buildAutoReplyPrompt(
                    contact: contact.displayLabel,
                    newMessage: message.text,
                    history: history,
                    memory: memory,
                    intent: intent
                )
            }

            let raw = try await ollama.generate(prompt: prompt)

            // Abstain sentinel from the model itself
            if ConversationContext.isInsufficientContext(raw) {
                print("[Abstain] \(contact.displayLabel): model returned INSUFFICIENT_CONTEXT")
                onAbstainedToDraft?(contact.id, "AI flagged this needs your input", "")
                return
            }

            var reply = ConversationContext.cleanLLMArtifacts(raw)
            reply = ConversationContext.enforceSpelling(reply, profile: liveContact.memory.styleProfile)
            reply = ConversationContext.enforceEmojiRate(reply, profile: liveContact.memory.styleProfile)
            reply = ConversationContext.scrubPII(reply)
            guard !reply.isEmpty else { return }

            // Parrot guard: reject if the reply is essentially just echoing back the
            // incoming message or one of the user's own recent messages.
            let parrotComparisons: [String] = mergedMessages.map { $0.text } +
                history.filter { $0.isFromMe }.suffix(8).map { $0.text }
            if ConversationContext.isParrot(reply, against: parrotComparisons) {
                print("[Parrot] \(contact.displayLabel): output too similar to recent messages, abstaining")
                onAbstainedToDraft?(contact.id, "AI parroted the conversation — draft manually", reply)
                return
            }

            let preference: AppleScriptRunner.ServicePreference = message.isSMS ? .sms : .iMessage
            try await sender.send(text: reply, to: message.contactID, allowSMS: allowSMSReplies, prefer: preference)
            lastReplyTime[contact.id] = Date()
            onAutoReplySent?(contact.id, mergedMessages.last?.text ?? message.text, reply)

            await maybeRefreshMemory(for: contact, addedCount: mergedMessages.count)
        } catch {
            onError?("Reply failed for \(contact.id): \(error.localizedDescription)")
        }
    }

    private func maybeRefreshMemory(for contact: Contact, addedCount: Int) async {
        let live = contactProvider?(contact.id) ?? contact
        var memory = live.memory
        memory.messagesSinceLastSummary += addedCount

        // Memory seeding is now done eagerly before the reply (see handleIncomingMessage).
        // This path only handles INCREMENTAL refreshes once the watermark threshold is hit.
        if !memory.isEmpty && memory.messagesSinceLastSummary >= memorySummarizer.watermarkThreshold {
            print("[Memory] Incremental refresh for \(contact.displayLabel) (\(memory.messagesSinceLastSummary) new msgs)")
            if let refreshed = await memorySummarizer.refreshMemory(for: live) {
                onMemoryUpdated?(contact.id, refreshed)
                return
            }
        }
        // Just persist the watermark increment
        onMemoryUpdated?(contact.id, memory)
    }

    func generateDraft(for contact: Contact) async -> String? {
        guard !contact.handles.isEmpty else { return nil }

        do {
            // Lazy-seed memory if missing, same as auto-reply path
            var live = contact
            if live.memory.isEmpty {
                print("[Memory] Seeding initial memory for \(live.displayLabel) before first draft")
                if let seeded = await memorySummarizer.refreshMemory(for: live) {
                    onMemoryUpdated?(contact.id, seeded)
                    live.memory = seeded
                }
            } else if live.memory.styleProfile.isEmpty {
                if let style = memorySummarizer.refreshStyleOnly(for: live) {
                    live.memory.styleProfile = style
                    onMemoryUpdated?(contact.id, live.memory)
                }
            }

            let history = try dbService.fetchUnifiedHistory(forHandles: live.handles, limit: 20)
            let memory = live.memory.isEmpty ? nil : live.memory
            let prompt = ConversationContext.buildDraftPrompt(contact: live.displayLabel, history: history, memory: memory)
            let raw = try await ollama.generate(prompt: prompt)
            var draft = ConversationContext.cleanLLMArtifacts(raw)
            draft = ConversationContext.enforceSpelling(draft, profile: live.memory.styleProfile)
            draft = ConversationContext.enforceEmojiRate(draft, profile: live.memory.styleProfile)
            draft = ConversationContext.scrubPII(draft)
            return draft.isEmpty ? nil : draft
        } catch {
            onError?("Draft generation failed: \(error.localizedDescription)")
            return nil
        }
    }
}
