# AutoMsg v2 — Suggested Enhancements

Categorized by impact and effort. Items at the top are the highest-leverage; items at the bottom are nice-to-haves.

## High Impact

### 1. Smart auto-reply triggers — not every message gets a reply
Right now, every incoming message from an enabled contact gets auto-replied. v2 should be smarter:
- **Only when busy/away**: tie auto-reply to macOS Focus modes (DND, Sleep, Work). When Focus is off, it's a draft, not an auto-send.
- **Only after delay**: don't fire instantly. Wait 30s — if you reply manually, cancel the auto-reply. ("snooze auto-reply for 30s after every incoming")
- **Question detector**: only auto-reply to actual questions or messages requiring response. Skip "lol", "ok", reactions.
- **Time-of-day rules**: no auto-replies between 11pm-7am unless explicitly opted in.

### 2. Per-contact persona / instructions
A free-text "instructions for the AI when replying to this person" field per contact. Examples:
- "This is my mom — be sweet, never use slang, always be reassuring"
- "This is a recruiter — keep it brief, professional, and don't commit to anything"
- "This is my best friend — be unhinged, no filter"

Stored on Contact, prepended to the prompt before the privacy rules.

### 3. Conversation memory beyond last 20 messages
Right now only the last 20 messages feed the LLM. v2:
- Periodically summarize older history into a per-contact "memory blob" (e.g. once a week the model writes "Things I should know about X: their birthday is May 12, their dog Cooper passed away in March, they prefer being called by middle name…")
- Stored in JSON, prepended to every prompt
- User-editable in the contact detail view

### 4. Cloud LLM fallback when Ollama is slow/down
Optional: register a Gemini/Claude/OpenAI API key. When Ollama is unreachable or response is taking >10s, fall back to cloud. Privacy guardrails still apply. Free tier of Gemini Flash is generous (60 req/min) — basically free for personal use.

### 5. Native iOS companion app
You already have the HTTP API. Build a SwiftUI iOS target that:
- Talks to the same `/api/*` endpoints
- Receives push notifications via APNs when a draft is ready (Mac side runs a local APNs forwarder or relay)
- Adds Siri Shortcuts ("Hey Siri, send the draft to Mom")
- ~1 week of work, $99/yr Apple Developer Program

## Medium Impact

### 6. Image / attachment understanding
Right now images appear as `[📎 image.png]` in the thread. With a multimodal Ollama model (`llava`, `llama3.2-vision`):
- Read images attached to incoming messages
- Generate replies that reference them ("nice sunset!" / "lol where is that?")
- Suggest captions for outgoing images

### 7. Reply scheduler
Compose a draft now, schedule it to send later. "Send this in 2 hours" / "Send tomorrow at 9am". Uses macOS UserNotifications to queue.

### 8. Conversation summaries
For long threads, a "Summarize" button that gives you bullet-point summary of what's been discussed. Useful for catching up after being away.

### 9. Sentiment / urgency dashboard
Top of the contact list shows badges:
- 🔴 "3 messages, 2 days no reply" — for important contacts
- 🟡 "Asking a question" — flagged questions across all contacts
- 🟢 "All caught up"
Driven by an Ollama pass over recent unanswered threads.

### 10. Multiple model presets
- "Quick mode" → llama3.2:1b (faster, terser replies)
- "Quality mode" → mistral:7b or qwen2.5:14b (better, slower)
- "Heavy mode" → llama3.3:70b for the GPU-rich (you mentioned a desktop with GPUs in your Hermes setup)
Toggle per-contact or globally.

### 11. Group chat support
Currently filtered out (`chat.style = 45`). v2 supports group chats with a separate flag — generate a group-aware draft that addresses the right person, or auto-reply only when you're @mentioned by name.

### 12. Activity heatmap
Visual: when do you and each contact actually message each other? Helps you decide who's worth enabling auto-reply for vs draft mode.

## Lower Impact / Nice-to-Have

### 13. Custom prompt template editor
Power users: edit the actual `buildAutoReplyPrompt` template in-app. Live preview of the prompt that would be generated for the selected contact.

### 14. Draft history per contact
Keep last 10 drafts you sent for each contact, so you can see how the AI's tone has evolved or revert to a previous draft style.

### 15. Voice-to-draft
Hold a hotkey, dictate "tell Mom I'll be there for dinner", AutoMsg drafts and sends. Uses macOS Speech framework (free, on-device).

### 16. Tailscale integration for off-network remote
Auto-detect Tailscale, surface the Tailscale IP in the Remote Access screen so the iPhone works from anywhere, not just same WiFi.

### 17. Backup / restore prefs
Export contacts, drafts, and settings as a JSON file. Useful when migrating Macs or reinstalling.

### 18. Themes / customization
Light mode option (currently dark only via system colors). Custom accent color. App icon variants.

### 19. Auto-update mechanism
Sparkle.framework integration so AutoMsg can check for new releases on your GitHub repo and auto-update. Standard for non-App-Store macOS apps.

### 20. Telemetry (opt-in, local-only)
A "stats" tab: how many auto-replies sent today, average response time, which contacts you message most, how often the AI's draft was sent vs edited vs dismissed. All local, never transmitted.

## Architecture / Tech Debt

### 21. Move from polling to real-time
Currently polls chat.db every 3s. Better:
- File system events on `~/Library/Messages/chat.db` and `chat.db-wal`
- Reduces latency from 3s to ~100ms on incoming messages

### 22. Proper unit tests
Currently zero test coverage. v2 should have tests for:
- PII scrubber regex (high-value, easy to write)
- Handle normalization
- Conversation context building
- Server endpoint routing

### 23. Notarized build via GitHub Actions
Replace ad-hoc signing with proper notarized release builds on tag push. Removes the "right-click → Open" friction for end users. Needs Apple Developer cert ($99/yr).

### 24. Localization
Currently English only. Pull strings into `.strings` files, translate at least Spanish + French.

### 25. Handle the chat.db service evolution
Apple keeps changing the schema (RCS support is recent). Detect schema version on open and adapt queries instead of hardcoding column names.

## My top 5 recommendations to do first

If you only do five, in this order:

1. **#1 Smart triggers + Focus mode integration** — the current "auto-reply to everything" is too aggressive in practice. This is the difference between v1 being "neat demo" and v2 being "I actually leave this on."
2. **#2 Per-contact persona** — huge quality jump for almost no code. One text field per contact.
3. **#5 Native iOS app** — you said this is the goal. The HTTP API is already there.
4. **#21 Real-time chat.db monitoring** — replaces polling, makes the whole thing feel snappy.
5. **#23 Notarized builds** — removes the Gatekeeper friction so other people can install without weird warnings.
