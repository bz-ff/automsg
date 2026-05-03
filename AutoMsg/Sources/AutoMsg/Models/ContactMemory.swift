import Foundation

enum RelationshipType: String, Codable, CaseIterable, Hashable {
    case unknown
    case closeFriend = "close_friend"
    case friend
    case family
    case romantic
    case professional
    case acquaintance
    case service

    var label: String {
        switch self {
        case .unknown: return "Unknown"
        case .closeFriend: return "Close friend"
        case .friend: return "Friend"
        case .family: return "Family"
        case .romantic: return "Romantic"
        case .professional: return "Professional / work"
        case .acquaintance: return "Acquaintance"
        case .service: return "Service / transactional"
        }
    }

    var emoji: String {
        switch self {
        case .unknown: return "❔"
        case .closeFriend: return "🤝"
        case .friend: return "👋"
        case .family: return "💛"
        case .romantic: return "❤️"
        case .professional: return "💼"
        case .acquaintance: return "👤"
        case .service: return "🧾"
        }
    }

    /// Tone guidance fed into the prompt for each relationship.
    var toneRules: String {
        switch self {
        case .unknown:
            return "Tone: neutral, observe before committing. Warm but not too familiar."
        case .closeFriend:
            return "Tone: very casual, banter, react like a close friend. Slang and humor are welcome."
        case .friend:
            return "Tone: friendly and casual but not overly familiar. Match the conversation's energy."
        case .family:
            return "Tone: warm, considerate. Show care. Avoid sarcasm unless conversation history shows it's normal."
        case .romantic:
            return "Tone: affectionate within the user's voice. Don't be performative."
        case .professional:
            return "Tone: clear, polite, direct. No slang. No casual abbreviations. Respond like a colleague would."
        case .acquaintance:
            return "Tone: friendly but reserved. Brief. Don't assume closeness."
        case .service:
            return "Tone: factual, concise, polite. No banter. No filler. Get to the point."
        }
    }
}

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
    var relationship: RelationshipType = .unknown
    var relationshipUserOverride: Bool = false      // if true, summarizer won't change it
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
