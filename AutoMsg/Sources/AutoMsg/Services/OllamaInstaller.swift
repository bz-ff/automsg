import Foundation
import AppKit

@MainActor
final class OllamaInstaller: ObservableObject {
    @Published var pullProgress: Double = 0.0
    @Published var pullStatus: String = ""
    @Published var serverStarting: Bool = false

    private let baseURL = URL(string: "http://localhost:11434")!

    /// Common locations the `ollama` binary may live
    private let candidatePaths = [
        "/usr/local/bin/ollama",
        "/opt/homebrew/bin/ollama",
        "/Applications/Ollama.app/Contents/Resources/ollama",
        "\(NSHomeDirectory())/.local/bin/ollama"
    ]

    func ollamaBinaryPath() -> String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func isInstalled() -> Bool {
        ollamaBinaryPath() != nil
    }

    func isRunning() async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        req.timeoutInterval = 2
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Spawn `ollama serve` in the background. Returns once the API is reachable, or throws.
    func startServer() async throws {
        if await isRunning() { return }
        guard let path = ollamaBinaryPath() else {
            throw OllamaInstallerError.notInstalled
        }

        serverStarting = true
        defer { serverStarting = false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        // Wait up to 10 seconds for the API to come up
        for _ in 0..<20 {
            if await isRunning() { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        throw OllamaInstallerError.serverDidNotStart
    }

    /// Pull a model and stream progress. The /api/pull endpoint returns newline-delimited JSON.
    func pullModel(_ name: String) async throws {
        let url = baseURL.appendingPathComponent("api/pull")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 600
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "stream": true])

        pullProgress = 0
        pullStatus = "Connecting…"

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OllamaInstallerError.pullFailed("HTTP \(((response as? HTTPURLResponse)?.statusCode).map(String.init) ?? "?")")
        }

        for try await line in bytes.lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let status = obj["status"] as? String { pullStatus = status }
            if let completed = obj["completed"] as? Int64,
               let total = obj["total"] as? Int64,
               total > 0 {
                pullProgress = Double(completed) / Double(total)
            }
            if let err = obj["error"] as? String {
                throw OllamaInstallerError.pullFailed(err)
            }
        }

        pullStatus = "Done"
        pullProgress = 1.0
    }

    /// Check if a specific model is already installed locally
    func hasModel(_ name: String) async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return false }
            return models.contains { ($0["name"] as? String)?.hasPrefix(name) == true }
        } catch {
            return false
        }
    }

    func openOllamaDownloadPage() {
        if let url = URL(string: "https://ollama.com/download/mac") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum OllamaInstallerError: Error, LocalizedError {
    case notInstalled
    case serverDidNotStart
    case pullFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "Ollama is not installed"
        case .serverDidNotStart: return "Ollama server didn't start within 10 seconds"
        case .pullFailed(let m): return "Model download failed: \(m)"
        }
    }
}
