import Foundation

enum MessageIntent: String, Codable {
    case question         // direct question expecting an answer
    case logistics        // factual info / coordinates ("park opens at 10")
    case statusShare      // "we are at epic universe" / "im up"
    case planInvitation   // "wanna grab food?" / "down for tonight?"
    case newsPositive     // "got the job!" / "we're engaged"
    case newsNegative     // "lost my phone" / "cat passed"
    case vent             // venting, complaining, frustrated
    case banter           // joke, roast, teasing
    case disagreement     // pushback, argument
    case confession       // emotional disclosure, vulnerability
    case flirt            // flirty, affectionate
    case requestHelp      // asks for assistance
    case smallTalk        // filler, "what's up", "hey"
    case needsUser        // genuinely insufficient context — user-specific question

    /// What posture the AI should adopt for this kind of message.
    var responseGuide: String {
        switch self {
        case .question:
            return "Answer directly if you can. If the answer is something only the user knows (their plans, schedule, choices), do NOT make it up — output INSUFFICIENT_CONTEXT instead."
        case .logistics:
            return "Brief acknowledgment with optional natural commentary. Do NOT echo their info back. Do NOT say 'got it' or 'noted'."
        case .statusShare:
            return "React like a friend reading what they're doing — show interest, well-wishes, or banter depending on the relationship. Do NOT acknowledge as a task. Do NOT echo their message back. Examples of good reactions: 'oh nice', 'have fun', 'lmk how it is', 'lol enjoy'."
        case .planInvitation:
            return "Respond with availability/intent. If you can't commit on the user's behalf without info they only have, output INSUFFICIENT_CONTEXT."
        case .newsPositive:
            return "Genuine congratulations matching the relationship's intensity. Don't overdo it for non-close contacts."
        case .newsNegative:
            return "Empathy first. No problem-solving unless asked. Match the relationship's closeness."
        case .vent:
            return "Validate, don't fix. Empathize. Match their energy. No lectures."
        case .banter:
            return "Match the energy. Banter back. Don't be a buzzkill."
        case .disagreement:
            return "Engage if the relationship supports it. Don't be sycophantic. Don't escalate either."
        case .confession:
            return "Slow down. Acknowledge the weight. Do NOT deflect with humor unless that is clearly the relationship's pattern. If unsure, output INSUFFICIENT_CONTEXT."
        case .flirt:
            return "Match the contact's tone if the relationship is romantic. Otherwise stay friendly without flirting."
        case .requestHelp:
            return "Respond with capacity. If the user actually has to do something, output INSUFFICIENT_CONTEXT — don't promise on their behalf."
        case .smallTalk:
            return "Brief, equal-energy small talk. One short message."
        case .needsUser:
            return "OUTPUT EXACTLY: INSUFFICIENT_CONTEXT"
        }
    }
}

@MainActor
final class IntentClassifier {
    private let ollama: OllamaService

    init(ollama: OllamaService) {
        self.ollama = ollama
    }

    /// Classify the latest incoming message. Returns the intent + a confidence flag.
    /// On any error or low confidence, returns nil so callers can default sensibly.
    func classify(message: String, recentContext: [ChatMessage]) async -> MessageIntent? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Cheap heuristics first to avoid an LLM call when obvious
        if trimmed.contains("?") {
            // Don't auto-return .question — questions can also be banter ("u even up?")
            // but it's a strong signal; let LLM confirm with this hint
        }

        let contextSnippet = recentContext.suffix(8).map { msg in
            "\(msg.isFromMe ? "[ME]" : "[THEM]") \(msg.text)"
        }.joined(separator: "\n")

        let prompt = """
        Classify the LATEST incoming text message. Output ONE label and nothing else.

        Recent thread for context:
        \(contextSnippet)

        Latest incoming message: "\(trimmed)"

        Possible labels (pick exactly one):
        - question: a direct question expecting an answer
        - logistics: factual info, coordinates, address, time ("park opens at 10")
        - status_share: sharing what they're doing, where they are, how they feel
        - plan_invitation: proposing plans or invitation to do something
        - news_positive: sharing good news (got job, engaged, etc.)
        - news_negative: sharing bad news (sick, lost X, etc.)
        - vent: venting, complaining, frustrated about something
        - banter: joke, roast, teasing, sarcasm
        - disagreement: pushback, argument
        - confession: emotional disclosure, vulnerability
        - flirt: flirty, affectionate
        - request_help: asks for help with something
        - small_talk: greetings, filler, "what's up"
        - needs_user: question only the user themselves can answer (their schedule, plans, opinions on user-specific things)

        Output exactly one label, lowercase with underscores. No explanation.
        """

        let response = (try? await ollama.generate(prompt: prompt)) ?? ""
        let normalized = response.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .first ?? ""

        // Strip trailing punctuation
        let cleaned = normalized.trimmingCharacters(in: CharacterSet.punctuationCharacters)
        let mapping: [String: MessageIntent] = [
            "question": .question,
            "logistics": .logistics,
            "status_share": .statusShare,
            "plan_invitation": .planInvitation,
            "news_positive": .newsPositive,
            "news_negative": .newsNegative,
            "vent": .vent,
            "banter": .banter,
            "disagreement": .disagreement,
            "confession": .confession,
            "flirt": .flirt,
            "request_help": .requestHelp,
            "small_talk": .smallTalk,
            "needs_user": .needsUser
        ]
        return mapping[cleaned]
    }
}
