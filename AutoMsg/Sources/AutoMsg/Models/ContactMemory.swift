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
            if avgLength < 20 { rules.append("Keep it SHORT — typically under 20 characters") }
            else if avgLength < 40 { rules.append("Keep it moderately short — 20-40 characters") }
            else { rules.append("Length can vary — typically 40-80 characters") }
        }
        if emojiRate < 0.05 {
            rules.append("DO NOT use emojis. This person almost never uses them.")
        } else if emojiRate < 0.15 {
            rules.append("Avoid emojis. Only use one if absolutely necessary (less than 1 in 10 messages).")
        } else if emojiRate < 0.35 {
            rules.append("Use emojis sparingly — at most 1 in every 4 messages.")
        } else if emojiRate > 0.6 {
            rules.append("Use emojis frequently (this person uses them in most messages).")
        }
        // Otherwise (0.35–0.6 range), leave the model to model emoji frequency from examples

        // Critical: only allow abbreviations the user actually uses, and FORBID inventing new ones
        if !commonAbbreviations.isEmpty {
            rules.append("ONLY these abbreviations are allowed: \(commonAbbreviations.joined(separator: ", ")). Do NOT invent text-speak.")
        } else {
            rules.append("Do NOT use text-speak abbreviations like 'u', 'ur', '2moro', 'dat', 'dis', 'tho'. Spell words normally.")
        }
        if !commonPhrases.isEmpty { rules.append("Common phrases this person uses: \(commonPhrases.joined(separator: ", "))") }

        rules.append("FORBIDDEN: 'dat', 'dis', '2moro', '2nite', 'dis', 'gud', 'plz', 'pls' unless they appear in EXAMPLES below")
        rules.append("Do not write phonetically or use 'baby talk' spelling")

        var output = "STYLE RULES (must follow exactly):\n"
        output += rules.map { "- \($0)" }.joined(separator: "\n")

        if !examples.isEmpty {
            output += "\n\nEXAMPLES — these are real messages the person sent. Match their EXACT spelling, length, and tone. Do not deviate from this voice:\n"
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
