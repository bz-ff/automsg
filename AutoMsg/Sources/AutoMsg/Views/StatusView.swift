import SwiftUI

struct StatusView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            statusDot(active: appState.ollamaConnected, label: "Ollama")
            statusDot(active: appState.messagesAvailable, label: "Messages")
            statusDot(active: appState.monitor.isRunning, label: "Monitor")
            statusDot(active: appState.remoteServerRunning, label: "Server")
        }
    }

    private func statusDot(active: Bool, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
