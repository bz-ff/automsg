import SwiftUI

struct ContactListView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText: String = ""
    @State private var showEnabledOnly: Bool = false
    @State private var showHistoryOnly: Bool = false

    private var filteredContacts: [Contact] {
        var list = appState.contacts
        if showEnabledOnly {
            list = list.filter { $0.isEnabled }
        }
        if showHistoryOnly {
            list = list.filter { $0.hasHistory }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return list }
        return list.filter { contact in
            contact.displayName.lowercased().contains(query) ||
            contact.id.lowercased().contains(query) ||
            contact.handles.contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Contacts")
                    .font(.headline)
                Spacer()
                Toggle("Active", isOn: $appState.isGlobalEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            HStack(spacing: 10) {
                Toggle("Enabled", isOn: $showEnabledOnly)
                    .toggleStyle(.checkbox)
                    .controlSize(.mini)
                    .font(.caption)
                Toggle("With history", isOn: $showHistoryOnly)
                    .toggleStyle(.checkbox)
                    .controlSize(.mini)
                    .font(.caption)
                Spacer()
                Text("\(filteredContacts.count)/\(appState.contacts.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            Divider()

            if !appState.diskAccessGranted {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text("Full Disk Access Required")
                        .font(.headline)
                    Text("Open System Settings > Privacy & Security > Full Disk Access and add AutoMsg.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List(selection: $appState.selectedContactID) {
                    ForEach(filteredContacts) { contact in
                        ContactRowView(contact: contact)
                            .tag(contact.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

struct ContactRowView: View {
    @EnvironmentObject var appState: AppState
    let contact: Contact

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(contact.isEnabled ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(contact.displayLabel)
                        .font(.system(.body, design: .default))
                        .lineLimit(1)
                    if contact.hasHistory {
                        Image(systemName: "message.fill")
                            .font(.caption2)
                            .foregroundColor(.blue.opacity(0.6))
                    }
                }

                if contact.isEnabled {
                    Text("Auto-reply on")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { contact.isEnabled },
                set: { _ in appState.toggleContact(contact.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
