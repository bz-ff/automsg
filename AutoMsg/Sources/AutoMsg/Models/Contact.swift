import Foundation

struct Contact: Identifiable, Codable, Hashable {
    let id: String
    var displayName: String
    var handles: [String]
    var isEnabled: Bool
    var currentDraft: String?
    var hasHistory: Bool = false
    var preferredHandle: String? = nil
    var memory: ContactMemory = ContactMemory()
    var smartMode: SmartMode = .moderate

    enum SmartMode: String, Codable {
        case alwaysAuto      // ignore gates, reply to everything (today's behavior)
        case moderate        // grace window + ack/length skip + user-replied-first cancel
        case focusOnly       // moderate + only when macOS Focus is on
        case draftOnly       // never auto-send, just draft
        case off
    }

    var displayLabel: String {
        displayName.isEmpty ? id : displayName
    }

    var primaryHandle: String {
        handles.first ?? id
    }

    func matches(handle: String) -> Bool {
        handles.contains(handle) || handles.contains(normalize(handle)) || id == handle
    }

    private func normalize(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        if digits.count == 10 { return "+1" + digits }
        if digits.count == 11, digits.first == "1" { return "+" + digits }
        if digits.count > 0 { return "+" + digits }
        return raw.lowercased()
    }
}
