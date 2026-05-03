import Foundation

/// Deterministically extracts a texting-style profile from the user's actual
/// messages to a specific contact. No LLM required — pure pattern analysis.
enum StyleAnalyzer {
    /// Common texting abbreviations / shortenings to detect
    private static let abbreviationCandidates: [String] = [
        "u", "ur", "ya", "yea", "yh", "tho", "bc", "btw", "rn", "asap",
        "lmk", "ily", "ngl", "tbh", "idk", "imo", "fr", "smh", "tmrw",
        "ttyl", "wyd", "hbu", "nm", "hru", "dunno", "gonna", "wanna",
        "kinda", "sorta", "ima", "ima'", "outta", "y'all", "yall"
    ]

    private static let phraseCandidates: [String] = [
        "lol", "lmao", "rofl", "haha", "lmaoo", "lmaooo",
        "fr", "fr fr", "ngl", "tbh", "idk", "smh",
        "no cap", "deadass", "facts", "bet", "word",
        "bruh", "bro", "yo", "yoo", "yooo"
    ]

    /// Build a style profile from the user's messages within the unified history.
    static func analyze(messages: [ChatMessage]) -> UserStyleProfile {
        let userMessages = messages
            .filter { $0.isFromMe && !$0.text.isEmpty }
            .map { $0.text }

        guard !userMessages.isEmpty else { return UserStyleProfile() }

        // Take the most recent ~50 messages for the analysis (recent style trumps old)
        let sample = Array(userMessages.suffix(50))

        var profile = UserStyleProfile()
        profile.avgLength = sample.map { $0.count }.reduce(0, +) / sample.count

        // Lowercase analysis: look at messages that have at least 3 letters
        let withLetters = sample.filter { msg in
            msg.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        }
        let lowercaseCount = withLetters.filter { $0 == $0.lowercased() }.count
        profile.lowercaseOnly = !withLetters.isEmpty && Double(lowercaseCount) / Double(withLetters.count) > 0.7

        // Period analysis: how often do messages end with a period?
        let withSentences = sample.filter { $0.count > 5 }
        let endsWithPeriod = withSentences.filter { $0.trimmingCharacters(in: .whitespaces).hasSuffix(".") }.count
        profile.omitsPeriods = !withSentences.isEmpty && Double(endsWithPeriod) / Double(withSentences.count) < 0.2

        // Lowercase 'i' habit
        let lowercaseIRegex = try? NSRegularExpression(pattern: #"(?:^|\s)i(?=\s|$|[',.!?])"#, options: [])
        let capitalIRegex = try? NSRegularExpression(pattern: #"(?:^|\s)I(?=\s|$|[',.!?])"#, options: [])
        var lowerIHits = 0, upperIHits = 0
        for msg in sample {
            let range = NSRange(msg.startIndex..., in: msg)
            lowerIHits += lowercaseIRegex?.numberOfMatches(in: msg, range: range) ?? 0
            upperIHits += capitalIRegex?.numberOfMatches(in: msg, range: range) ?? 0
        }
        if (lowerIHits + upperIHits) >= 3 {
            profile.avoidsCapitalI = lowerIHits > upperIHits * 2
        }

        // Emoji rate
        let withEmoji = sample.filter { msg in
            msg.unicodeScalars.contains { $0.properties.isEmoji && $0.value > 0x238C }
        }.count
        profile.emojiRate = Double(withEmoji) / Double(sample.count)

        // Abbreviation usage — count how many candidates appear in the sample
        let allText = sample.joined(separator: " ").lowercased()
        let words = Set(allText.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map { String($0) })
        profile.commonAbbreviations = abbreviationCandidates
            .filter { abbrev in
                // Look for whole-word matches
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: abbrev))\\b"
                let regex = try? NSRegularExpression(pattern: pattern, options: [])
                let matches = regex?.numberOfMatches(in: allText, range: NSRange(allText.startIndex..., in: allText)) ?? 0
                return matches >= 2  // appears at least twice
            }
            .prefix(8)
            .map { $0 }
        _ = words  // silence unused warning if compiler complains

        // Common phrases (full-substring match)
        profile.commonPhrases = phraseCandidates
            .filter { phrase in
                let count = allText.components(separatedBy: phrase).count - 1
                return count >= 2
            }
            .prefix(6)
            .map { $0 }

        // Examples — pick 8 recent messages that aren't ack-only/single-emoji,
        // span varied lengths, prefer ones with letters
        let candidates = userMessages
            .filter { $0.count >= 2 }
            .filter { msg in msg.unicodeScalars.contains { CharacterSet.letters.contains($0) } }
            .suffix(40)
        var picked: [String] = []
        // Take a varied sample: every Nth message from the recent 40
        let step = max(1, candidates.count / 8)
        var idx = 0
        for msg in candidates {
            if idx % step == 0 { picked.append(msg) }
            idx += 1
            if picked.count >= 8 { break }
        }
        // If we still don't have enough, pad with the most recent
        if picked.count < 6 {
            picked = Array(candidates.suffix(8))
        }
        profile.examples = picked

        return profile
    }
}
