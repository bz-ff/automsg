import Foundation
import Contacts

struct ResolvedContact {
    let identifier: String
    let name: String
    let handles: [String]
}

final class ContactsResolver {
    private let store = CNContactStore()
    private var nameByHandle: [String: String] = [:]
    private var handlesByName: [String: [String]] = [:]
    private(set) var allContacts: [ResolvedContact] = []
    private var loaded = false

    func requestAccess() async -> Bool {
        if CNContactStore.authorizationStatus(for: .contacts) == .authorized { return true }
        return await withCheckedContinuation { cont in
            store.requestAccess(for: .contacts) { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    func loadAll() async {
        guard await requestAccess() else { return }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]

        let containers = (try? store.containers(matching: nil)) ?? []
        var collected: [ResolvedContact] = []

        for container in containers {
            let predicate = CNContact.predicateForContactsInContainer(withIdentifier: container.identifier)
            let contacts = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
            for contact in contacts {
                let name = Self.formatName(contact)
                guard !name.isEmpty else { continue }

                var handles: [String] = []
                for phone in contact.phoneNumbers {
                    let normalized = Self.normalizePhone(phone.value.stringValue)
                    self.nameByHandle[normalized] = name
                    handles.append(normalized)
                }
                for email in contact.emailAddresses {
                    let addr = (email.value as String).lowercased()
                    self.nameByHandle[addr] = name
                    handles.append(addr)
                }

                guard !handles.isEmpty else { continue }
                let unique = Array(Set(handles))
                self.handlesByName[name, default: []].append(contentsOf: unique)
                collected.append(ResolvedContact(
                    identifier: contact.identifier,
                    name: name,
                    handles: unique
                ))
            }
        }

        // Dedupe by name (merge handles across containers)
        var byName: [String: ResolvedContact] = [:]
        for c in collected {
            if var existing = byName[c.name] {
                let merged = Array(Set(existing.handles + c.handles))
                byName[c.name] = ResolvedContact(identifier: existing.identifier, name: c.name, handles: merged)
            } else {
                byName[c.name] = c
            }
        }
        self.allContacts = byName.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
        self.loaded = true
        print("ContactsResolver: loaded \(self.allContacts.count) iCloud contacts")
    }

    func name(for handle: String) -> String? {
        if let direct = nameByHandle[handle] { return direct }
        let normalized = Self.normalizePhone(handle)
        if let match = nameByHandle[normalized] { return match }
        return nameByHandle[handle.lowercased()]
    }

    func handles(forName name: String) -> [String] {
        return handlesByName[name] ?? []
    }

    private static func formatName(_ contact: CNContact) -> String {
        let first = contact.givenName.trimmingCharacters(in: .whitespaces)
        let last = contact.familyName.trimmingCharacters(in: .whitespaces)
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        if !full.isEmpty { return full }
        return contact.organizationName.trimmingCharacters(in: .whitespaces)
    }

    private static func normalizePhone(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        if digits.count == 10 { return "+1" + digits }
        if digits.count == 11, digits.first == "1" { return "+" + digits }
        if digits.count > 0 { return "+" + digits }
        return raw.lowercased()
    }
}
