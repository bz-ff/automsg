import Foundation

struct UserStyleProfile: Codable, Hashable {
    var lowercaseOnly: Bool = false
    var omitsPeriods: Bool = false
    var avgLength: Int = 0           // average characters in user's messages to this contact
    var emojiRate: Double = 0        // emojis per message (0.0 = never, 1.0 = ~one per msg)
    var commonAbbreviations: [String] = []   // "u", "ur", "lmk", "rn", etc.
    var commonPhrases: [String] = []         // "lol", "fr", "ngl"
    var avoidsCapitalI: Bool = false         // writes "i" not "I"
    var examples: [String] = []              // 6-10 actual messages from user to this contact

    var isEmpty: Bool { avgLength == 0 && examples.isEmpty }

    func formattedForPrompt() -> String {
        var rules: [String] = []
        if lowercaseOnly { rules.append("Write in ALL LOWERCASE only — never capitalize") }
        if omitsPeriods { rules.append("Don't use periods at the end of messages") }
        if avoidsCapitalI { rules.append("Write 'i' lowercase, never 'I'") }
        if avgLength > 0 {
            if avgLength < 20 { rules.append("Keep messages SHORT — typically under 20 characters, often just a few words") }
            else if avgLength < 40 { rules.append("Keep messages moderately short — typically 20-40 characters") }
            else { rules.append("Messages can be a bit longer — typically 40-80 characters") }
        }
        if emojiRate < 0.1 { rules.append("Rarely use emojis (less than 1 in 10 messages)") }
        else if emojiRate > 0.5 { rules.append("Frequently use emojis (about half of messages)") }
        if !commonAbbreviations.isEmpty { rules.append("Use these abbreviations naturally: \(commonAbbreviations.joined(separator: ", "))") }
        if !commonPhrases.isEmpty { rules.append("Frequently use phrases like: \(commonPhrases.joined(separator: ", "))") }

        var output = "STYLE RULES (must follow exactly):\n"
        output += rules.map { "- \($0)" }.joined(separator: "\n")

        if !examples.isEmpty {
            output += "\n\nEXAMPLES of how the person actually texts (mimic this voice exactly):\n"
            output += examples.map { "→ \($0)" }.joined(separator: "\n")
        }

        return output
    }
}

struct ContactMemory: Codable, Hashable {
    var summary: String = ""
    var facts: [String] = []
    var openLoops: [String] = []
    var preferences: [String] = []
    var styleProfile: UserStyleProfile = UserStyleProfile()
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
