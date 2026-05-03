import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var availableModels: [OllamaModel] = []
    @State private var selectedModel: String = Persistence.modelName
    @State private var loading = true
    @State private var saved: Bool = false
    @State private var ollamaErr: String?

    struct OllamaModel: Identifiable {
        let id: String       // e.g. "qwen2.5:7b"
        let sizeGB: Double
        let modified: String
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section(title: "AI Model") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Currently active:")
                                    .foregroundColor(.secondary)
                                Text(Persistence.modelName)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundColor(.green)
                                    .cornerRadius(5)
                            }

                            if loading {
                                ProgressView("Loading installed models…")
                                    .controlSize(.small)
                            } else if let err = ollamaErr {
                                Text(err)
                                    .foregroundColor(.red)
                                    .font(.callout)
                            } else if availableModels.isEmpty {
                                Text("No models installed. Install one with `ollama pull qwen2.5:7b` in Terminal.")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(availableModels) { model in
                                    HStack {
                                        Image(systemName: model.id == selectedModel ? "circle.inset.filled" : "circle")
                                            .foregroundColor(model.id == selectedModel ? .accentColor : .secondary)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(model.id).font(.system(.body, design: .monospaced))
                                            Text("\(String(format: "%.1f", model.sizeGB)) GB · modified \(model.modified)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 4)
                                    .onTapGesture {
                                        selectedModel = model.id
                                    }
                                }

                                HStack {
                                    Button("Apply") {
                                        Persistence.modelName = selectedModel
                                        saved = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
                                    }
                                    .controlSize(.large)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(selectedModel == Persistence.modelName)

                                    Button("Refresh list") { loadModels() }
                                        .controlSize(.large)

                                    if saved {
                                        Text("Saved · restart AutoMsg to take effect")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding(.top, 6)

                                Text("Tip: 7B+ models give noticeably better style mimicry than 3B. Recommended: qwen2.5:7b or mistral:7b.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                    }

                    section(title: "Quiet Hours") {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Skip auto-replies during quiet hours", isOn: Binding(
                                get: { appState.monitor.smartTriggers.quietHoursEnabled },
                                set: { appState.monitor.smartTriggers.quietHoursEnabled = $0 }
                            ))
                            Text("Default window: 11pm–7am. Applies only to contacts in Smart or Focus mode.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    section(title: "Diagnostics") {
                        VStack(alignment: .leading, spacing: 4) {
                            row("Ollama URL", "http://localhost:11434")
                            row("Server URL", appState.remoteIPURL)
                            row("Pending replies", "\(appState.monitor.pendingAutoReplies)")
                            row("Setup complete", appState.setupComplete ? "yes" : "no")
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 520, height: 620)
        .onAppear { loadModels() }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            content()
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)
        }
    }

    private func row(_ key: String, _ val: String) -> some View {
        HStack {
            Text(key).foregroundColor(.secondary)
            Spacer()
            Text(val).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
        .font(.callout)
    }

    private func loadModels() {
        loading = true
        ollamaErr = nil
        Task {
            do {
                let url = URL(string: "http://localhost:11434/api/tags")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let raw = (json?["models"] as? [[String: Any]]) ?? []
                let parsed = raw.compactMap { dict -> OllamaModel? in
                    guard let name = dict["name"] as? String else { return nil }
                    let size = (dict["size"] as? Int64).map { Double($0) / 1_073_741_824.0 } ?? 0
                    let modAt = (dict["modified_at"] as? String) ?? ""
                    let short = modAt.prefix(10).description
                    return OllamaModel(id: name, sizeGB: size, modified: short)
                }
                self.availableModels = parsed.sorted { $0.id < $1.id }
                self.loading = false
            } catch {
                self.ollamaErr = "Couldn't reach Ollama: \(error.localizedDescription)"
                self.loading = false
            }
        }
    }
}
