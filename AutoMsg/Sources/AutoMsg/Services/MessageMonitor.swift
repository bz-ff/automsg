import Foundation
import Combine

@MainActor
final class MessageMonitor: ObservableObject {
    @Published var isRunning = false

    private let dbService: ChatDatabaseService
    private let ollama: OllamaService
    private let sender: MessageSender
    private var timer: Timer?
    private var lastProcessedROWID: Int64
    private var lastReplyTime: [String: Date] = [:]
    private let minReplyInterval: TimeInterval = 5
    private var isProcessing = false

    var onAutoReplySent: ((String, String, String) -> Void)?
    var onDraftGenerated: ((String, String) -> Void)?
    var onError: ((String) -> Void)?

    init(dbService: ChatDatabaseService, ollama: OllamaService, sender: MessageSender) {
        self.dbService = dbService
        self.ollama = ollama
        self.sender = sender
        self.lastProcessedROWID = Persistence.lastProcessedROWID
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

        let enabledContacts = contacts.filter { $0.isEnabled }
        guard !enabledContacts.isEmpty else { return }

        do {
            let newMessages = try dbService.fetchNewMessages(afterROWID: lastProcessedROWID)

            for message in newMessages {
                lastProcessedROWID = max(lastProcessedROWID, message.id)
                Persistence.lastProcessedROWID = lastProcessedROWID

                guard let matched = enabledContacts.first(where: { $0.matches(handle: message.contactID) }) else {
                    continue
                }

                if let lastReply = lastReplyTime[matched.id],
                   Date().timeIntervalSince(lastReply) < minReplyInterval {
                    continue
                }

                let cutoff = Date().addingTimeInterval(-60)
                guard message.date > cutoff else { continue }

                await handleIncomingMessage(message, contactKey: matched.id)
            }
        } catch {
            onError?("Poll error: \(error.localizedDescription)")
        }
    }

    var allowSMSReplies: Bool = false

    var unifiedHistoryProvider: ((String) -> [ChatMessage])?

    private func handleIncomingMessage(_ message: ChatMessage, contactKey: String) async {
        do {
            // Pull unified history across all handles for this contact (matches Messages.app behavior)
            let unified = unifiedHistoryProvider?(contactKey) ?? []
            let history = unified.isEmpty
                ? (try dbService.fetchConversationHistory(chatIdentifier: message.chatIdentifier, limit: 20))
                : unified

            let prompt = ConversationContext.buildAutoReplyPrompt(
                contact: contactKey,
                newMessage: message.text,
                history: history
            )

            let raw = try await ollama.generate(prompt: prompt)
            let reply = ConversationContext.scrubPII(raw)
            guard !reply.isEmpty else { return }

            // Mirror the incoming service: SMS in -> SMS out, iMessage in -> iMessage out
            let preference: AppleScriptRunner.ServicePreference = message.isSMS ? .sms : .iMessage
            try await sender.send(text: reply, to: message.contactID, allowSMS: allowSMSReplies, prefer: preference)
            lastReplyTime[contactKey] = Date()
            onAutoReplySent?(contactKey, message.text, reply)
        } catch {
            onError?("Reply failed for \(contactKey): \(error.localizedDescription)")
        }
    }

    func generateDraft(for contact: Contact) async -> String? {
        guard !contact.handles.isEmpty else { return nil }

        do {
            let history = try dbService.fetchUnifiedHistory(forHandles: contact.handles, limit: 20)
            let prompt = ConversationContext.buildDraftPrompt(contact: contact.displayLabel, history: history)
            let raw = try await ollama.generate(prompt: prompt)
            let draft = ConversationContext.scrubPII(raw)
            return draft.isEmpty ? nil : draft
        } catch {
            onError?("Draft generation failed: \(error.localizedDescription)")
            return nil
        }
    }
}
