import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showRemote = false
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            ContactListView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            if let selectedID = appState.selectedContactID,
               let contact = appState.contacts.first(where: { $0.id == selectedID }) {
                ContactDetailView(contact: contact)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a contact")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showRemote = true
                } label: {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                }
                .help("Remote Access")
            }
            ToolbarItem(placement: .automatic) {
                StatusView()
            }
        }
        .sheet(isPresented: $showRemote) {
            RemoteAccessView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
