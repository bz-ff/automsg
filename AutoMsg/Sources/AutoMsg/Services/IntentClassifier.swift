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
    /// Includes concrete grounding examples — what to do AND what to avoid.
    var responseGuide: String {
        switch self {
        case .question:
            return """
            They asked a question. Answer directly using what you actually know from the conversation history. \
            If the answer requires user-only info (their plans, opinions, schedule), output INSUFFICIENT_CONTEXT. \
            DO NOT ask a clarifying question that they already answered in the message itself.
            """
        case .logistics:
            return """
            They shared factual info (a time, place, or plan detail). React naturally:
            - Acknowledge with light commentary that references what they said specifically
            - Or ask a NEW follow-up that builds on the info — not one they already answered
            FORBIDDEN: "got it" / "noted" / "okay" / echoing their info back / asking about a detail they already provided.
            EXAMPLE: They say "park opens at 10" → good: "oof, long line then?" / "well at least its early" / "lol u camping out?". Bad: "what time again?", "what about the park?"
            """
        case .statusShare:
            return """
            They're sharing what they're doing or where they are. React with brief warmth/interest:
            - Reference what they specifically said
            - Show you read it (acknowledgment + small reaction)
            - Optionally extend with a related follow-up that fits the moment
            FORBIDDEN: asking about info they ALREADY shared. Echoing their message back. "Got it" / "okay" responses.
            EXAMPLE: They say "we checked in to the hotel, left the park at 7:30" → good: "nice, long day?" / "u tired?" / "any good rides?" / "ok rest up". Bad: "wyd abt park?" / "when did u leave the park?" (they JUST told you).
            """
        case .planInvitation:
            return """
            They proposed plans or invited the user to something. Respond with intent or availability.
            If committing requires info only the user knows (calendar, preference, budget), output INSUFFICIENT_CONTEXT.
            FORBIDDEN: vague non-answers like "sure!" / "sounds good!" without engaging the actual proposal.
            """
        case .newsPositive:
            return """
            They shared good news. Match the relationship intensity with congratulations:
            - Reference WHAT they're celebrating, not generic "congrats"
            - For close contacts, more enthusiastic. For acquaintances, brief and warm.
            FORBIDDEN: generic "that's great!" without engaging the specific news.
            """
        case .newsNegative:
            return """
            They shared bad news. Empathy first, no problem-solving:
            - Acknowledge what specifically happened
            - Show care without giving advice unless asked
            FORBIDDEN: jumping to solutions. Toxic positivity ("everything happens for a reason"). Minimizing.
            """
        case .vent:
            return """
            They're venting. Validate their feeling, don't fix:
            - Reflect what they specifically said
            - Match their energy
            FORBIDDEN: lectures, advice they didn't ask for, "have you tried..." responses.
            """
        case .banter:
            return """
            They're joking/teasing. Match the energy:
            - Banter back at the same level
            - Don't go meta ("haha that's funny")
            FORBIDDEN: explaining why something is funny, breaking the rhythm with seriousness.
            """
        case .disagreement:
            return """
            They pushed back. Engage if the relationship allows it:
            - Don't be sycophantic ("you're so right")
            - Don't escalate either
            - Acknowledge their point THEN respond
            """
        case .confession:
            return """
            They opened up emotionally. Slow down:
            - Acknowledge what they shared specifically
            - Match the weight; don't deflect with humor unless that's clearly your pattern
            If unsure, output INSUFFICIENT_CONTEXT — let the user respond personally.
            """
        case .flirt:
            return """
            Flirty/affectionate message. Match the contact's tone IF the relationship is romantic.
            Otherwise stay friendly without flirting back.
            """
        case .requestHelp:
            return """
            They asked for help. If the user actually has to do something physical or specific to them,
            output INSUFFICIENT_CONTEXT — don't promise on their behalf. Otherwise respond with capacity.
            """
        case .smallTalk:
            return """
            Greeting or filler. One brief, matched-energy message.
            FORBIDDEN: long replies. Generic "how was your day" follow-ups unless that's the pattern.
            """
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
