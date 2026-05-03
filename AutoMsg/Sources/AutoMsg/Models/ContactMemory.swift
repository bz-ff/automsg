import Foundation

struct ContactMemory: Codable, Hashable {
    var summary: String = ""
    var facts: [String] = []
    var openLoops: [String] = []
    var preferences: [String] = []
    var lastSummarizedROWID: Int64 = 0
    var lastSummarizedAt: Date? = nil
    var messagesSinceLastSummary: Int = 0

    var isEmpty: Bool {
        summary.isEmpty && facts.isEmpty && openLoops.isEmpty && preferences.isEmpty
    }

    func formattedForPrompt() -> String? {
        guard !isEmpty else { return nil }
        var lines: [String] = []
        if !summary.isEmpty { lines.append("Summary: \(summary)") }
        if !facts.isEmpty {
            lines.append("Facts I know about this person:")
            lines.append(contentsOf: facts.map { "- \($0)" })
        }
        if !openLoops.isEmpty {
            lines.append("Open loops (unresolved threads with this person):")
            lines.append(contentsOf: openLoops.map { "- \($0)" })
        }
        if !preferences.isEmpty {
            lines.append("Their preferences / things to watch for:")
            lines.append(contentsOf: preferences.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }
}
