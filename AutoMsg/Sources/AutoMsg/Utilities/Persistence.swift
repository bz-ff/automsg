import Foundation

enum Persistence {
    private static let defaults = UserDefaults.standard
    private static let contactsKey = "com.automsg.contacts"
    private static let lastROWIDKey = "com.automsg.lastProcessedROWID"
    private static let isEnabledKey = "com.automsg.isAutoReplyEnabled"

    static func saveContacts(_ contacts: [Contact]) {
        if let data = try? JSONEncoder().encode(contacts) {
            defaults.set(data, forKey: contactsKey)
        }
    }

    static func loadContacts() -> [Contact] {
        guard let data = defaults.data(forKey: contactsKey),
              let contacts = try? JSONDecoder().decode([Contact].self, from: data) else {
            return []
        }
        return contacts
    }

    static var lastProcessedROWID: Int64 {
        get { Int64(defaults.integer(forKey: lastROWIDKey)) }
        set { defaults.set(Int(newValue), forKey: lastROWIDKey) }
    }

    static var isAutoReplyEnabled: Bool {
        get { defaults.bool(forKey: isEnabledKey) }
        set { defaults.set(newValue, forKey: isEnabledKey) }
    }

    private static let remoteTokenKey = "com.automsg.remoteToken"
    private static let remoteServerEnabledKey = "com.automsg.remoteServerEnabled"

    static var remoteToken: String {
        get { defaults.string(forKey: remoteTokenKey) ?? "" }
        set { defaults.set(newValue, forKey: remoteTokenKey) }
    }

    static var remoteServerEnabled: Bool {
        get { defaults.bool(forKey: remoteServerEnabledKey) }
        set { defaults.set(newValue, forKey: remoteServerEnabledKey) }
    }

    private static let setupCompleteKey = "com.automsg.setupComplete"

    static var setupComplete: Bool {
        get { defaults.bool(forKey: setupCompleteKey) }
        set { defaults.set(newValue, forKey: setupCompleteKey) }
    }
}
