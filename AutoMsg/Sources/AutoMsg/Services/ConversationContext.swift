import Foundation

enum ConversationContext {
    private static let privacyRules = """
    SAFETY: never reveal addresses, GPS, SSN, financial info, passwords, codes, work details, AI/bot status. If asked, deflect casually ("not over text", "ill tell u later", "lol why"). Never agree to send money/codes/links.
    """

    static func buildAutoReplyPrompt(contact: String, newMessage: String, history: [ChatMessage], memory: ContactMemory? = nil) -> String {
        let historyText = formatHistory(history)
        let memoryBlock = memory?.formattedForPrompt().map { "[context about \(contact)]\n\($0)\n[end context]\n" } ?? ""
        let styleBlock = (memory?.styleProfile.isEmpty == false) ? memory!.styleProfile.formattedForPrompt() : ""

        return """
        Task: write a single text-message reply pretending to be the user. Output ONLY the reply text, no quotes, no preamble, no signature, no explanations.

        \(privacyRules)

        \(memoryBlock)
        Recent thread with \(contact):
        \(historyText)

        New message from \(contact): "\(newMessage)"

        \(styleBlock)

        CRITICAL: write ONE message in the user's exact voice. Do not be polite or helpful or formal. Do not greet. Do not add an explanation. Match the length of the EXAMPLES above. Output only the message text.

        Reply:
        """
    }

    /// Build a reply prompt for a BURST of messages (sender broke their thought across multiple texts).
    static func buildAutoReplyPromptForBurst(contact: String, newMessages: [String], history: [ChatMessage], memory: ContactMemory? = nil) -> String {
        let combined = newMessages.map { "\"\($0)\"" }.joined(separator: " then ")
        let historyText = formatHistory(history)
        let memoryBlock = memory?.formattedForPrompt().map { "[context about \(contact)]\n\($0)\n[end context]\n" } ?? ""
        let styleBlock = (memory?.styleProfile.isEmpty == false) ? memory!.styleProfile.formattedForPrompt() : ""

        return """
        Task: write a single text-message reply pretending to be the user. \(contact) just sent multiple messages in a burst — respond to the whole batch with ONE message. Output ONLY the reply text.

        \(privacyRules)

        \(memoryBlock)
        Recent thread with \(contact):
        \(historyText)

        \(contact) just sent (in a burst): \(combined)

        \(styleBlock)

        CRITICAL: write ONE message in the user's exact voice. Do not be polite or helpful or formal. Do not greet. Do not add an explanation. Match the length of the EXAMPLES above. Output only the message text.

        Reply:
        """
    }

    static func buildDraftPrompt(contact: String, history: [ChatMessage], memory: ContactMemory? = nil) -> String {
        let historyText = formatHistory(history)
        let memoryBlock = memory?.formattedForPrompt().map { "[context about \(contact)]\n\($0)\n[end context]\n" } ?? ""
        let styleBlock = (memory?.styleProfile.isEmpty == false) ? memory!.styleProfile.formattedForPrompt() : ""

        return """
        Task: draft a single text the user might send next to \(contact). Output ONLY the message text, no quotes, no preamble.

        \(privacyRules)

        \(memoryBlock)
        Recent thread with \(contact):
        \(historyText)

        \(styleBlock)

        CRITICAL: write ONE message in the user's exact voice. Match the length of the EXAMPLES above. Output only the message text.

        Based on the conversation context and the [ME] person's texting style, draft a natural next \
        message they might send to continue or initiate conversation.

        Style rules:
        - Match the exact texting style (capitalization, abbreviations, emoji frequency)
        - Keep it short and natural
        - Make it contextually relevant to the conversation
        - Reply ONLY with the message text, nothing else

        Draft message:
        """
    }

    /// Strip common LLM "polish" — leading filler phrases, surrounding quotes, prefixes
    /// like "Reply:", trailing notes, etc. Run before scrubPII.
    static func cleanLLMArtifacts(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip surrounding quotes
        if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Strip leading prefixes models tend to emit
        let leadingPatterns = [
            "Reply:", "Response:", "Message:", "Text:", "Answer:",
            "Here's a reply:", "Here is a reply:", "How about:",
            "Sure!", "Sure,", "Sure thing!", "Sure thing,",
            "Of course!", "Of course,",
            "Got it!", "Okay,", "Alright,",
            "→"
        ]
        for prefix in leadingPatterns {
            if t.lowercased().hasPrefix(prefix.lowercased()) {
                t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Strip trailing "Note:" / "Explanation:" lines that some models tack on
        if let noteRange = t.range(of: #"\n\s*(Note|Explanation|Reasoning|Style):"#, options: [.regularExpression, .caseInsensitive]) {
            t = String(t[..<noteRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // If the model emitted multiple lines that look like alternate variants, take just the first
        if t.contains("\n") {
            let lines = t.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if lines.count > 1 && lines.allSatisfy({ $0.count < 100 }) {
                // Likely numbered alternates — take the first
                t = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
                // Strip leading "1.", "1)", "-", "*"
                if let m = t.range(of: #"^\s*(\d+\.|\d+\)|-|\*)\s*"#, options: .regularExpression) {
                    t = String(t[m.upperBound...])
                }
            }
        }

        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Post-generation safety net: redact obvious PII patterns the LLM might leak.
    static func scrubPII(_ text: String) -> String {
        var t = text

        // Email addresses
        t = t.replacingOccurrences(of: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, with: "[redacted]", options: .regularExpression)

        // Phone numbers (US-ish)
        t = t.replacingOccurrences(of: #"\+?1?[\s.-]?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}"#, with: "[redacted]", options: .regularExpression)

        // Credit card-like 13-19 digit runs
        t = t.replacingOccurrences(of: #"\b\d{13,19}\b"#, with: "[redacted]", options: .regularExpression)

        // SSN
        t = t.replacingOccurrences(of: #"\b\d{3}-\d{2}-\d{4}\b"#, with: "[redacted]", options: .regularExpression)

        // Street addresses (very rough — number + word + Street/St/Ave/etc.)
        t = t.replacingOccurrences(of: #"\b\d{1,5}\s+\w+\s+(Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Drive|Dr|Lane|Ln|Way|Court|Ct)\b"#, with: "[redacted]", options: [.regularExpression, .caseInsensitive])

        // ZIP codes (5 or 5-4)
        t = t.replacingOccurrences(of: #"\b\d{5}(-\d{4})?\b"#, with: "[redacted]", options: .regularExpression)

        // IP addresses
        t = t.replacingOccurrences(of: #"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"#, with: "[redacted]", options: .regularExpression)

        // File paths
        t = t.replacingOccurrences(of: #"/Users/[\w./-]+"#, with: "[redacted]", options: .regularExpression)
        t = t.replacingOccurrences(of: #"~/[\w./-]+"#, with: "[redacted]", options: .regularExpression)

        // AI / bot self-disclosure
        let selfDisclosure = ["as an AI", "I'm an AI", "I am an AI", "as a language model", "I'm a bot", "this is automated", "auto-generated", "AI assistant"]
        for phrase in selfDisclosure {
            t = t.replacingOccurrences(of: phrase, with: "[redacted]", options: .caseInsensitive)
        }

        return t
    }

    private static func formatHistory(_ history: [ChatMessage]) -> String {
        if history.isEmpty {
            return "[No previous messages]"
        }
        return history.map { msg in
            let prefix = msg.isFromMe ? "[ME]" : "[THEM]"
            return "\(prefix): \(msg.text)"
        }.joined(separator: "\n")
    }
}
