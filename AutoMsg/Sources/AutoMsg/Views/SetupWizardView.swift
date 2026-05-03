import SwiftUI
import AppKit

struct SetupWizardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var installer = OllamaInstaller()

    @State private var step: WizardStep = .welcome
    @State private var ollamaInstallPolling: Timer?
    @State private var serverStartError: String?
    @State private var pullError: String?

    enum WizardStep: Int, CaseIterable {
        case welcome, installOllama, startServer, pullModel, permissions, done
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            Divider()
            footer
        }
        .frame(width: 580, height: 520)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 28))
                .foregroundStyle(LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading) {
                Text("Welcome to AutoMsg")
                    .font(.title.bold())
                Text("Quick setup — about a minute")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            ProgressIndicator(current: step.rawValue, total: WizardStep.allCases.count - 1)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .installOllama: installOllamaStep
        case .startServer: startServerStep
        case .pullModel: pullModelStep
        case .permissions: permissionsStep
        case .done: doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "message.badge.waveform")
                .font(.system(size: 64))
                .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom))

            Text("AutoMsg replies to your iMessages with a local AI")
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                Label("Runs entirely on your Mac — nothing sent to the cloud", systemImage: "lock.shield.fill")
                Label("Mimics your texting style from past conversations", systemImage: "bubble.left.and.bubble.right.fill")
                Label("Always-ready drafts you can send with one tap", systemImage: "pencil.and.outline")
                Label("Control from your iPhone via the built-in remote", systemImage: "iphone.radiowaves.left.and.right")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            Text("We'll set up Ollama (a local AI runtime) and download a small model.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var installOllamaStep: some View {
        VStack(spacing: 18) {
            Image(systemName: installer.isInstalled() ? "checkmark.seal.fill" : "arrow.down.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(installer.isInstalled() ? .green : .blue)

            if installer.isInstalled() {
                Text("Ollama is installed")
                    .font(.title3.bold())
                Text(installer.ollamaBinaryPath() ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Text("Install Ollama")
                    .font(.title3.bold())
                Text("Ollama is the local AI runtime AutoMsg uses for replies. It's free and open source.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                Button {
                    installer.openOllamaDownloadPage()
                    startInstallPolling()
                } label: {
                    Label("Open ollama.com download page", systemImage: "safari")
                        .frame(maxWidth: 320)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                Text("After installing, this screen will continue automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if ollamaInstallPolling != nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Watching for Ollama installation…")
                            .font(.caption)
                    }
                }
            }
        }
        .onAppear {
            if installer.isInstalled() {
                advanceAfter(0.5)
            }
        }
    }

    private var startServerStep: some View {
        VStack(spacing: 18) {
            Image(systemName: installer.serverStarting ? "arrow.trianglehead.2.clockwise.rotate.90" : "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.blue)

            Text(installer.serverStarting ? "Starting Ollama…" : "Starting Ollama service")
                .font(.title3.bold())

            if let err = serverStartError {
                Text(err)
                    .font(.callout)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                Button("Retry") { startServerNow() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .onAppear { startServerNow() }
    }

    private var pullModelStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.down.circle.dotted")
                .font(.system(size: 56))
                .foregroundColor(.blue)

            Text("Downloading AI model")
                .font(.title3.bold())

            Text("llama3.2:3b · about 2 GB")
                .font(.callout)
                .foregroundColor(.secondary)

            VStack(spacing: 6) {
                ProgressView(value: installer.pullProgress)
                    .frame(maxWidth: 380)
                HStack {
                    Text(installer.pullStatus.isEmpty ? "Starting…" : installer.pullStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(installer.pullProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: 380)
            }

            if let err = pullError {
                Text(err)
                    .font(.callout)
                    .foregroundColor(.red)
                Button("Retry") { pullModelNow() }
                    .controlSize(.large)
            }
        }
        .onAppear { pullModelNow() }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Grant permissions")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .center)

            Text("AutoMsg needs three permissions to work:")
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            permissionRow(
                icon: "lock.doc",
                title: "Full Disk Access",
                desc: "To read your iMessage history. Click → System Settings → enable AutoMsg.",
                button: "Open Settings",
                action: { open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") }
            )
            permissionRow(
                icon: "person.text.rectangle",
                title: "Contacts",
                desc: "To show contact names instead of phone numbers.",
                button: "Open Settings",
                action: { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") }
            )
            permissionRow(
                icon: "wifi.router",
                title: "Local Network",
                desc: "So your iPhone can reach AutoMsg over WiFi for the remote.",
                button: "Open Settings",
                action: { open("x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") }
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var doneStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            Text("All set!")
                .font(.title.bold())
            Text("AutoMsg is ready. Click Finish to open the app.")
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }

    private func permissionRow(icon: String, title: String, desc: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(desc).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button(button, action: action)
                .controlSize(.small)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var footer: some View {
        HStack {
            if step != .welcome && step != .done {
                Button("Skip") { advance() }
                    .controlSize(.regular)
            }
            Spacer()
            primaryButton
        }
        .padding()
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .welcome:
            Button("Get Started") { advance() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .installOllama:
            Button("Continue") { advance() }
                .disabled(!installer.isInstalled())
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .startServer:
            EmptyView()
        case .pullModel:
            Button("Continue") { advance() }
                .disabled(installer.pullProgress < 1.0 && pullError == nil)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .permissions:
            Button("Continue") { advance() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .done:
            Button("Finish") {
                Persistence.setupComplete = true
                appState.setupComplete = true
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Actions

    private func advance() {
        let next = WizardStep(rawValue: step.rawValue + 1) ?? .done
        withAnimation { step = next }
    }

    private func advanceAfter(_ seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { advance() }
    }

    private func startInstallPolling() {
        ollamaInstallPolling?.invalidate()
        ollamaInstallPolling = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            Task { @MainActor in
                if installer.isInstalled() {
                    timer.invalidate()
                    ollamaInstallPolling = nil
                    advanceAfter(0.5)
                }
            }
        }
    }

    private func startServerNow() {
        serverStartError = nil
        Task {
            do {
                try await installer.startServer()
                advanceAfter(0.5)
            } catch {
                serverStartError = error.localizedDescription
            }
        }
    }

    private func pullModelNow() {
        pullError = nil
        Task {
            if await installer.hasModel("llama3.2:3b") {
                installer.pullProgress = 1.0
                installer.pullStatus = "Already installed"
                advanceAfter(0.5)
                return
            }
            do {
                try await installer.pullModel("llama3.2:3b")
            } catch {
                pullError = error.localizedDescription
            }
        }
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct ProgressIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i <= current ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}
