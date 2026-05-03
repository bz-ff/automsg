import Foundation
import SwiftUI
import Darwin

struct ActivityEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let contactID: String
    let type: EntryType
    let incomingText: String?
    let replyText: String

    enum EntryType {
        case autoReply
        case manualSend
    }

    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var isGlobalEnabled: Bool = false {
        didSet {
            Persistence.isAutoReplyEnabled = isGlobalEnabled
            if isGlobalEnabled {
                monitor.restart(contacts: contacts)
            } else {
                monitor.stop()
            }
        }
    }
    @Published var contacts: [Contact] = [] {
        didSet {
            Persistence.saveContacts(contacts)
            if isGlobalEnabled {
                monitor.restart(contacts: contacts)
            }
        }
    }
    @Published var selectedContactID: String?
    @Published var activityLog: [ActivityEntry] = []
    @Published var ollamaConnected: Bool = false
    @Published var messagesAvailable: Bool = false
    @Published var isGeneratingDraft: Bool = false
    @Published var diskAccessGranted: Bool = true
    @Published var diskAccessError: String?
    @Published var lastSendInfo: String?
    @Published var lastSendError: String?
    @Published var allowSMSFallback: Bool = false {
        didSet { monitor.allowSMSReplies = allowSMSFallback }
    }
    @Published var remoteServerEnabled: Bool = false
    @Published var remoteServerRunning: Bool = false
    @Published var remoteToken: String = ""
    @Published var setupComplete: Bool = Persistence.setupComplete
    private var iMessageHandles: Set<String> = []
    private var remoteServer: RemoteServer?

    let dbService = ChatDatabaseService()
    let ollama = OllamaService()
    let sender = MessageSender()
    let contactsResolver = ContactsResolver()
    lazy var monitor: MessageMonitor = {
        let m = MessageMonitor(dbService: dbService, ollama: ollama, sender: sender)
        m.onAutoReplySent = { [weak self] contactID, incoming, reply in
            Task { @MainActor in
                self?.addActivity(contactID: contactID, type: .autoReply, incoming: incoming, reply: reply)
                await self?.regenerateDraft(for: contactID)
            }
        }
        m.onError = { [weak self] msg in
            print("AutoMsg Error: \(msg)")
        }
        m.unifiedHistoryProvider = { [weak self] contactKey in
            guard let self,
                  let c = self.contacts.first(where: { $0.id == contactKey }) else { return [] }
            return (try? self.dbService.fetchUnifiedHistory(forHandles: c.handles, limit: 20)) ?? []
        }
        return m
    }()

    private var healthTimer: Timer?

    func bootstrap() {
        contacts = Persistence.loadContacts()
        isGlobalEnabled = Persistence.isAutoReplyEnabled
        remoteToken = Persistence.remoteToken
        remoteServerEnabled = Persistence.remoteServerEnabled

        if isGlobalEnabled {
            monitor.start(contacts: contacts)
        }

        if remoteServerEnabled {
            startRemoteServer()
        }

        startHealthChecks()
        discoverNewContacts()
    }

    func shutdown() {
        monitor.stop()
        healthTimer?.invalidate()
        dbService.close()
        remoteServer?.stop()
        Persistence.saveContacts(contacts)
    }

    var remoteURL: String {
        // Prefer the actual mDNS hostname (no apostrophes/special chars). Fall back to IP.
        let bonjour = Self.bonjourHostname()
        if let bonjour {
            return "http://\(bonjour):8765/?token=\(remoteToken)"
        }
        let ip = Self.localIPAddress() ?? "localhost"
        return "http://\(ip):8765/?token=\(remoteToken)"
    }

    var remoteIPURL: String {
        let ip = Self.localIPAddress() ?? "localhost"
        return "http://\(ip):8765/?token=\(remoteToken)"
    }

    private static func bonjourHostname() -> String? {
        // Use ProcessInfo's hostname which is the system mDNS name (sanitized by macOS)
        var hostname = ProcessInfo.processInfo.hostName
        // hostName comes back like "Yours-MacBook-Pro.local" — already URL-safe in modern macOS
        // but if it contains anything weird, drop to IP
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        if hostname.unicodeScalars.allSatisfy({ allowed.contains($0) }) && hostname.contains(".local") {
            return hostname
        }
        // Sanitize: strip apostrophes, lowercase, replace spaces with dashes
        hostname = hostname.replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        if hostname.unicodeScalars.allSatisfy({ allowed.contains($0) }) && hostname.contains(".local") {
            return hostname
        }
        return nil
    }

    private static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(interface.ifa_addr,
                                   socklen_t(interface.ifa_addr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: hostname)
                        if address?.starts(with: "192.") == true || address?.starts(with: "10.") == true {
                            return address
                        }
                    }
                }
            }
        }
        return address
    }

    func setRemoteServerEnabled(_ enabled: Bool) {
        remoteServerEnabled = enabled
        Persistence.remoteServerEnabled = enabled
        if enabled {
            startRemoteServer()
        } else {
            remoteServer?.stop()
            remoteServer = nil
            remoteServerRunning = false
        }
    }

    func rotateRemoteToken() {
        remoteToken = Self.generateToken()
        Persistence.remoteToken = remoteToken
        if remoteServerEnabled {
            remoteServer?.stop()
            startRemoteServer()
        }
    }

    private func startRemoteServer() {
        if remoteToken.isEmpty {
            remoteToken = Self.generateToken()
            Persistence.remoteToken = remoteToken
        }
        let server = RemoteServer(port: 8765, token: remoteToken, appState: self)
        server.start()
        remoteServer = server
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.remoteServerRunning = self?.remoteServer?.isRunning ?? false
        }
    }

    private static func generateToken() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<20).map { _ in chars.randomElement()! })
    }

    func sendDraft(for contactID: String) async {
        guard let index = contacts.firstIndex(where: { $0.id == contactID }),
              let draft = contacts[index].currentDraft, !draft.isEmpty else { return }

        let contact = contacts[index]
        let target = pickSendHandle(for: contact)
        guard let target else {
            lastSendError = "No valid handle for \(contact.displayName)"
            return
        }

        let imCapable = isIMessageCapable(target)
        let isEmail = target.contains("@")
        // Decide service preference up front — if we know it's SMS-only, don't even try iMessage
        let preference: AppleScriptRunner.ServicePreference
        if imCapable || isEmail {
            preference = .iMessage
        } else if allowSMSFallback {
            preference = .sms
        } else {
            // Phone with no iMessage history and SMS not allowed — try iMessage best-effort but it'll likely fail
            preference = .iMessage
        }
        print("[AutoMsg] Sending to handle: \(target) (iMessage-capable: \(imCapable), preference: \(preference), contact: \(contact.displayName), all handles: \(contact.handles))")
        lastSendError = nil

        do {
            let svc = try await sender.send(text: draft, to: target, allowSMS: allowSMSFallback, prefer: preference)
            lastSendInfo = "Sent via \(svc.rawValue) to \(target)"
            addActivity(contactID: contactID, type: .manualSend, incoming: nil, reply: draft)
            contacts[index].currentDraft = nil
            await regenerateDraft(for: contactID)
        } catch {
            print("[AutoMsg] Send failed: \(error.localizedDescription)")
            lastSendInfo = nil
            lastSendError = error.localizedDescription
        }
    }

    private func pickSendHandle(for contact: Contact) -> String? {
        if let preferred = contact.preferredHandle {
            return preferred
        }
        // Priority 1: handle that's confirmed iMessage-capable in chat.db
        if let imessage = contact.handles.first(where: { iMessageHandles.contains($0) }) {
            return imessage
        }
        // Priority 2: email (always iMessage on Apple devices)
        if let email = contact.handles.first(where: { $0.contains("@") }) {
            return email
        }
        // Priority 3: any handle with prior chat history
        for handle in contact.handles {
            if let _ = try? dbService.findChatIdentifier(forContact: handle) {
                return handle
            }
        }
        // Priority 4: first phone or any handle
        return contact.handles.first(where: { $0.hasPrefix("+") || $0.first?.isNumber == true })
            ?? contact.handles.first
    }

    func isIMessageCapable(_ handle: String) -> Bool {
        iMessageHandles.contains(handle)
    }

    func setPreferredHandle(_ handle: String?, for contactID: String) {
        guard let idx = contacts.firstIndex(where: { $0.id == contactID }) else { return }
        contacts[idx].preferredHandle = handle
    }

    func regenerateDraft(for contactID: String) async {
        guard let index = contacts.firstIndex(where: { $0.id == contactID }),
              contacts[index].isEnabled else { return }

        isGeneratingDraft = true
        let contact = contacts[index]
        let draft = await monitor.generateDraft(for: contact)
        if let draft {
            contacts[index].currentDraft = draft
        }
        isGeneratingDraft = false
    }

    func toggleContact(_ contactID: String) {
        guard let index = contacts.firstIndex(where: { $0.id == contactID }) else { return }
        contacts[index].isEnabled.toggle()

        if contacts[index].isEnabled {
            Task { await regenerateDraft(for: contactID) }
        } else {
            contacts[index].currentDraft = nil
        }
    }

    private func addActivity(contactID: String, type: ActivityEntry.EntryType, incoming: String?, reply: String) {
        let entry = ActivityEntry(
            timestamp: Date(), contactID: contactID,
            type: type, incomingText: incoming, replyText: reply
        )
        activityLog.insert(entry, at: 0)
        if activityLog.count > 50 { activityLog.removeLast() }
    }

    private func startHealthChecks() {
        healthTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.ollamaConnected = await self.ollama.checkHealth()
                self.messagesAvailable = self.sender.isAvailable()
            }
        }
        Task {
            ollamaConnected = await ollama.checkHealth()
            messagesAvailable = sender.isAvailable()
        }
    }

    private func discoverNewContacts() {
        Task {
            await contactsResolver.loadAll()

            let chatDBContacts: [Contact]
            do {
                chatDBContacts = try dbService.fetchAllContacts()
                iMessageHandles = (try? dbService.iMessageCapableHandles()) ?? []
                diskAccessGranted = true
                diskAccessError = nil
            } catch {
                diskAccessGranted = false
                diskAccessError = error.localizedDescription
                chatDBContacts = []
            }

            let chatHandles = Set(chatDBContacts.map { $0.id })

            var built: [Contact] = []
            var coveredHandles = Set<String>()

            // 1. All iCloud contacts first (so user can enable people they haven't messaged yet)
            for resolved in contactsResolver.allContacts {
                let hasHistory = resolved.handles.contains { chatHandles.contains($0) }
                coveredHandles.formUnion(resolved.handles)
                built.append(Contact(
                    id: resolved.name,
                    displayName: resolved.name,
                    handles: resolved.handles,
                    isEnabled: false,
                    currentDraft: nil,
                    hasHistory: hasHistory
                ))
            }

            // 2. Anyone in chat.db whose number isn't in iCloud (unknown senders)
            for raw in chatDBContacts where !coveredHandles.contains(raw.id) {
                if let name = contactsResolver.name(for: raw.id) { _ = name } // already covered
                built.append(Contact(
                    id: raw.id,
                    displayName: raw.id,
                    handles: [raw.id],
                    isEnabled: false,
                    currentDraft: nil,
                    hasHistory: true
                ))
            }

            built.sort {
                if $0.hasHistory != $1.hasHistory { return $0.hasHistory && !$1.hasHistory }
                return $0.displayName.lowercased() < $1.displayName.lowercased()
            }

            // Preserve existing isEnabled / currentDraft state by id
            let prev = Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, $0) })
            contacts = built.map { newContact in
                var c = newContact
                if let p = prev[c.id] {
                    c.isEnabled = p.isEnabled
                    c.currentDraft = p.currentDraft
                }
                return c
            }
        }
    }
}
