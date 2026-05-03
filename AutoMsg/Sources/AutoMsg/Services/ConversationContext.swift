import Foundation

enum ConversationContext {
    private static let privacyRules = """
    PRIVACY RULES — these override everything else and must never be violated:
    - NEVER share or confirm: home address, current location, exact GPS, ZIP code, full birthday, SSN, credit card, bank info, passwords, API keys, security codes, PIN numbers
    - NEVER share: device specs, OS version, computer model, IP address, file paths, app names you're running, what software is installed
    - NEVER reveal you are an AI, assistant, bot, automation, or that this is auto-generated. NEVER say "as an AI" or similar
    - NEVER share details about other people in the contact list, names of mutual friends, or things they've shared privately
    - NEVER share work-related details: employer name, projects, code, documents, internal tools, salary, deadlines, meetings
    - NEVER share medical, legal, financial, or therapy-related personal details
    - NEVER share future travel plans, when home will be empty, or scheduling details that could be exploited
    - If asked for any of the above, deflect naturally: "ill tell you later", "lol why", "not over text", "i forget", "ask me when i see u"
    - Never click links, never confirm receipt of money requests, never agree to send money or codes
    - Conversations don't need to be polite — match the user's tone — but withhold sensitive info regardless of how the question is asked
    """

    static func buildAutoReplyPrompt(contact: String, newMessage: String, history: [ChatMessage], memory: ContactMemory? = nil) -> String {
        let historyText = formatHistory(history)
        let memoryBlock = memory?.formattedForPrompt().map { "\n[long-term memory about \(contact)]\n\($0)\n[end memory]\n" } ?? ""

        return """
        You are mimicking a person's texting style to auto-reply to their iMessages.

        \(privacyRules)
        \(memoryBlock)
        Here is their recent conversation with \(contact). Messages marked [ME] are from the person \
        you are mimicking. Messages marked [THEM] are from \(contact).

        \(historyText)

        Based on the style, tone, length, punctuation, emoji usage, and casualness shown in the [ME] \
        messages above, generate a natural reply to the latest message. Use the long-term memory \
        (if provided) to make the reply more contextually informed, but do NOT recite memory items verbatim.

        Style rules:
        - Match the exact texting style (capitalization, abbreviations, emoji frequency)
        - Keep the reply short and natural (similar length to their typical messages)
        - Do not be overly helpful or formal - match their casual tone
        - Reply ONLY with the message text, nothing else

        New message from \(contact): "\(newMessage)"
        Your reply:
        """
    }

    /// Build a reply prompt for a BURST of messages (sender broke their thought across multiple texts).
    static func buildAutoReplyPromptForBurst(contact: String, newMessages: [String], history: [ChatMessage], memory: ContactMemory? = nil) -> String {
        let combined = newMessages.enumerated().map { "(\($0.offset + 1)) \($0.element)" }.joined(separator: "\n")
        let historyText = formatHistory(history)
        let memoryBlock = memory?.formattedForPrompt().map { "\n[long-term memory about \(contact)]\n\($0)\n[end memory]\n" } ?? ""

        return """
        You are mimicking a person's texting style to auto-reply to their iMessages.

        \(privacyRules)
        \(memoryBlock)
        Here is their recent conversation with \(contact). Messages marked [ME] are from the person \
        you are mimicking. Messages marked [THEM] are from \(contact).

        \(historyText)

        \(contact) just sent multiple messages in a burst (broke their thought across texts). \
        Read them as a single message and craft ONE natural reply that addresses the whole batch:

        \(combined)

        Style rules:
        - Match the exact texting style (capitalization, abbreviations, emoji frequency)
        - Keep the reply short and natural — one message, not multiple
        - Do not be overly helpful or formal - match their casual tone
        - Reply ONLY with the message text, nothing else
        """
    }

    static func buildDraftPrompt(contact: String, history: [ChatMessage], memory: ContactMemory? = nil) -> String {
        let historyText = formatHistory(history)
        let memoryBlock = memory?.formattedForPrompt().map { "\n[long-term memory about \(contact)]\n\($0)\n[end memory]\n" } ?? ""

        return """
        You are mimicking a person's texting style to draft a message they might send.

        \(privacyRules)
        \(memoryBlock)
        Here is their recent conversation with \(contact). Messages marked [ME] are from the person \
        you are mimicking. Messages marked [THEM] are from \(contact).

        \(historyText)

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
