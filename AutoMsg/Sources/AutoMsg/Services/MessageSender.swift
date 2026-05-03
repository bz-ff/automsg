import Foundation

final class MessageSender {
    @discardableResult
    func send(text: String, to contactID: String, allowSMS: Bool = false, prefer: AppleScriptRunner.ServicePreference = .auto) async throws -> AppleScriptRunner.SendService {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AppleScriptRunner.SendService, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let svc = try AppleScriptRunner.sendMessage(text: text, to: contactID, allowSMS: allowSMS, prefer: prefer)
                    continuation.resume(returning: svc)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func isAvailable() -> Bool {
        return AppleScriptRunner.isMessagesRunning()
    }
}
