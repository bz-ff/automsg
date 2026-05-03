import Foundation

final class OllamaService {
    private let baseURL: URL
    private let model: String
    private let session: URLSession

    init(baseURL: String = "http://localhost:11434", model: String = "llama3.2:3b") {
        self.baseURL = URL(string: baseURL)!
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    func generate(prompt: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": 0.5,            // tighter — sticks to instructions, less creative drift
                "top_p": 0.9,
                "repeat_penalty": 1.1,
                "num_predict": 120,
                "stop": ["\n\n", "Reply:", "\n→", "Note:", "Explanation:", "Note that", "Translation:"]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw OllamaError.invalidResponse
        }

        return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func checkHealth() async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

enum OllamaError: Error, LocalizedError {
    case requestFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .requestFailed: return "Ollama request failed"
        case .invalidResponse: return "Invalid response from Ollama"
        }
    }
}
