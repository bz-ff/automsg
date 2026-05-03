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
    }

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
            let unified = unifiedHistoryProvider?(contact.id) ?? []
            let history = unified.isEmpty
                ? (try dbService.fetchConversationHistory(chatIdentifier: message.chatIdentifier, limit: 20))
                : unified

            let liveContact = contactProvider?(contact.id) ?? contact
            let memory = liveContact.memory.isEmpty ? nil : liveContact.memory

            let prompt: String
            if mergedMessages.count > 1 {
                prompt = ConversationContext.buildAutoReplyPromptForBurst(
                    contact: contact.displayLabel,
                    newMessages: mergedMessages.map { $0.text },
                    history: history,
                    memory: memory
                )
            } else {
                prompt = ConversationContext.buildAutoReplyPrompt(
                    contact: contact.displayLabel,
                    newMessage: message.text,
                    history: history,
                    memory: memory
                )
            }

            let raw = try await ollama.generate(prompt: prompt)
            let reply = ConversationContext.scrubPII(raw)
            guard !reply.isEmpty else { return }

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

        if memory.messagesSinceLastSummary >= memorySummarizer.watermarkThreshold || memory.isEmpty {
            print("[Memory] Refreshing memory for \(contact.displayLabel)")
            if let refreshed = await memorySummarizer.refreshMemory(for: live) {
                onMemoryUpdated?(contact.id, refreshed)
                return
            }
        }
        onMemoryUpdated?(contact.id, memory)
    }

    func generateDraft(for contact: Contact) async -> String? {
        guard !contact.handles.isEmpty else { return nil }

        do {
            let history = try dbService.fetchUnifiedHistory(forHandles: contact.handles, limit: 20)
            let memory = contact.memory.isEmpty ? nil : contact.memory
            let prompt = ConversationContext.buildDraftPrompt(contact: contact.displayLabel, history: history, memory: memory)
            let raw = try await ollama.generate(prompt: prompt)
            let draft = ConversationContext.scrubPII(raw)
            return draft.isEmpty ? nil : draft
        } catch {
            onError?("Draft generation failed: \(error.localizedDescription)")
            return nil
        }
    }
}
