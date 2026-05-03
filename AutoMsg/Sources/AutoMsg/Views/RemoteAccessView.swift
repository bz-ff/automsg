import SwiftUI

struct RemoteAccessView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Remote Access")
                    .font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            ScrollView {
                content.padding()
            }
        }
        .frame(width: 460, height: 720)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 16) {

            HStack(spacing: 8) {
                Circle()
                    .fill(appState.remoteServerRunning ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(appState.remoteServerRunning ? "Server running on port 8765" : "Server stopped")
                    .font(.callout)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appState.remoteServerEnabled },
                    set: { appState.setRemoteServerEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            if appState.remoteServerRunning {
                let url = appState.remoteURL
                let qrURL = appState.remoteIPURL  // IP works more reliably on iOS than .local
                VStack(spacing: 12) {
                    if let img = QRCode.image(from: qrURL, size: 220) {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 220, height: 220)
                            .background(Color.white)
                            .cornerRadius(8)
                    }
                    Text("Scan with iPhone camera")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        VStack(spacing: 2) {
                            Text("Primary (mDNS)").font(.caption2).foregroundColor(.secondary)
                            Text(url)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .multilineTextAlignment(.center)
                                .padding(6)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(6)
                        }

                        VStack(spacing: 2) {
                            Text("Fallback (IP — try this if QR fails)").font(.caption2).foregroundColor(.secondary)
                            Text(appState.remoteIPURL)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .multilineTextAlignment(.center)
                                .padding(6)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(6)
                        }

                        HStack {
                            Button("Copy Primary") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url, forType: .string)
                            }
                            .controlSize(.small)
                            Button("Copy IP URL") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(appState.remoteIPURL, forType: .string)
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Setup")
                        .font(.headline)
                    Text("1. Connect iPhone to the same WiFi as this Mac")
                    Text("2. Scan the QR code with the Camera app")
                    Text("3. Tap the Safari banner to open the URL")
                    Text("4. Tap Share → Add to Home Screen for an app icon")
                }
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

                HStack {
                    Button("Rotate Token") {
                        appState.rotateRemoteToken()
                    }
                    Spacer()
                    Text("Token: \(String(appState.remoteToken.prefix(6)))…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            } else {
                Text("Enable the server to generate a pairing QR code.")
                    .foregroundColor(.secondary)
                    .padding()
            }

        }
    }
}
