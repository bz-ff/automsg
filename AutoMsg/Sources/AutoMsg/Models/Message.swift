import Foundation

struct ChatMessage: Identifiable {
    let id: Int64
    let text: String
    let isFromMe: Bool
    let date: Date
    let contactID: String
    let chatIdentifier: String
    let service: String
    let hasAttachment: Bool
    let attachmentInfo: String?

    var isSMS: Bool { service.uppercased() == "SMS" }

    var displayText: String {
        var parts: [String] = []
        if !text.isEmpty { parts.append(text) }
        if hasAttachment {
            if let info = attachmentInfo, !info.isEmpty {
                parts.append("📎 \(info)")
            } else {
                parts.append("📎 [attachment]")
            }
        }
        return parts.isEmpty ? "[empty]" : parts.joined(separator: "\n")
    }
}
