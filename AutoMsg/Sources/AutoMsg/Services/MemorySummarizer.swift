import Foundation

/// Periodically distills long-term context per contact into a compact memory blob
/// that gets prepended to every prompt.
@MainActor
final class MemorySummarizer {
    private let dbService: ChatDatabaseService
    private let ollama: OllamaService

    /// Trigger a refresh after this many new messages have accumulated since last summary
    var watermarkThreshold: Int = 50

    /// How many messages to feed the summarizer when seeding initial memory
    var initialSeedMessageLimit: Int = 200

    /// How many recent messages to feed the incremental updater
    var incrementalLookback: Int = 80

    init(dbService: ChatDatabaseService, ollama: OllamaService) {
        self.dbService = dbService
        self.ollama = ollama
    }

    /// Returns a refreshed memory blob, or nil if generation failed.
    /// Decides on its own whether to do an initial seed or an incremental update.
    func refreshMemory(for contact: Contact) async -> ContactMemory? {
        guard !contact.handles.isEmpty else { return nil }
        guard let history = try? dbService.fetchUnifiedHistory(
            forHandles: contact.handles,
            limit: contact.memory.isEmpty ? initialSeedMessageLimit : incrementalLookback
        ), !history.isEmpty else {
            return nil
        }

        let prompt = contact.memory.isEmpty
            ? Self.seedPrompt(contact: contact, history: history)
            : Self.incrementalPrompt(contact: contact, history: history)

        let raw = (try? await ollama.generate(prompt: prompt)) ?? ""
        let cleaned = ConversationContext.scrubPII(raw)
        guard !cleaned.isEmpty else { return nil }

        guard let parsed = parseJSON(cleaned) else {
            print("[MemorySummarizer] Failed to parse JSON from LLM. Raw: \(cleaned.prefix(200))")
            return nil
        }

        var newMemory = contact.memory
        newMemory.summary = parsed.summary
        newMemory.facts = parsed.facts
        newMemory.openLoops = parsed.openLoops
        newMemory.preferences = parsed.preferences
        // Always recompute the deterministic style profile from latest history
        newMemory.styleProfile = StyleAnalyzer.analyze(messages: history)
        newMemory.lastSummarizedAt = Date()
        newMemory.lastSummarizedROWID = history.map { $0.id }.max() ?? newMemory.lastSummarizedROWID
        newMemory.messagesSinceLastSummary = 0
        return newMemory
    }

    /// Update ONLY the style profile (cheap — no LLM call). Useful when you want
    /// a quick refresh of the user's voice without re-running the summarizer.
    func refreshStyleOnly(for contact: Contact) -> UserStyleProfile? {
        guard !contact.handles.isEmpty else { return nil }
        guard let history = try? dbService.fetchUnifiedHistory(forHandles: contact.handles, limit: 100) else {
            return nil
        }
        return StyleAnalyzer.analyze(messages: history)
    }

    // MARK: - Prompts

    private static func seedPrompt(contact: Contact, history: [ChatMessage]) -> String {
        let formatted = formatHistory(history)
        return """
        You are summarizing a text-message conversation history into structured memory
        for an AI that auto-replies on the user's behalf. The memory will be prepended
        to every future prompt, so it must be concise but information-dense.

        Conversation with \(contact.displayLabel):
        \(formatted)

        Output ONLY a JSON object with this exact schema (no commentary, no code fences):
        {
          "summary": "2-3 sentence description of who this person is to the user and the overall vibe of the relationship",
          "facts": ["concrete facts about this person worth remembering, one per item, terse"],
          "open_loops": ["unresolved threads or commitments the user owes this person"],
          "preferences": ["how this person likes to be talked to, topics to avoid, tone preferences"]
        }

        Rules:
        - NEVER include addresses, phone numbers, full birthdates, financial details, passwords, or other PII even if mentioned
        - Keep each item under 100 characters
        - 3-8 items per array; fewer is fine
        - If a category has no entries, return an empty array
        - Do NOT wrap in code fences or add any text before/after the JSON
        """
    }

    private static func incrementalPrompt(contact: Contact, history: [ChatMessage]) -> String {
        let formatted = formatHistory(history)
        let existing = contact.memory
        let existingJSON = (try? JSONSerialization.data(
            withJSONObject: [
                "summary": existing.summary,
                "facts": existing.facts,
                "open_loops": existing.openLoops,
                "preferences": existing.preferences
            ],
            options: [.prettyPrinted]
        )).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return """
        You are updating long-term memory about a person based on new messages.

        EXISTING MEMORY:
        \(existingJSON)

        RECENT MESSAGES with \(contact.displayLabel):
        \(formatted)

        Update the memory to reflect new information. Add new facts, mark resolved
        open loops as removed, refine the summary if context shifted.

        Output ONLY the updated JSON object (same schema as input, no commentary):
        {
          "summary": "...",
          "facts": [...],
          "open_loops": [...],
          "preferences": [...]
        }

        Rules:
        - Preserve facts that are still true; remove ones that are clearly stale or contradicted
        - Move resolved open loops out (delete them); add new ones
        - NEVER include addresses, phone numbers, full birthdates, financial details, passwords, PII
        - Keep each item under 100 characters
        - Do NOT wrap in code fences or add any text before/after the JSON
        """
    }

    private static func formatHistory(_ history: [ChatMessage]) -> String {
        history.map { msg in
            let prefix = msg.isFromMe ? "[ME]" : "[THEM]"
            return "\(prefix): \(msg.text)"
        }.joined(separator: "\n")
    }

    // MARK: - Parsing

    private struct ParsedMemory {
        var summary: String
        var facts: [String]
        var openLoops: [String]
        var preferences: [String]
    }

    private func parseJSON(_ raw: String) -> ParsedMemory? {
        // Tolerate stray text — find the first { and last } to bound the JSON
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"),
              start <= end else { return nil }
        let slice = String(raw[start...end])
        guard let data = slice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return ParsedMemory(
            summary: (obj["summary"] as? String) ?? "",
            facts: (obj["facts"] as? [String]) ?? [],
            openLoops: (obj["open_loops"] as? [String]) ?? [],
            preferences: (obj["preferences"] as? [String]) ?? []
        )
    }
}
