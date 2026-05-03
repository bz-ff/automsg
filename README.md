# AutoMsg

A native macOS SwiftUI app that auto-replies to incoming iMessages and SMS using a local Ollama LLM, with always-ready AI-generated drafts per contact and an iPhone remote-control web UI.

## Features

- **Auto-reply** to incoming messages from selected contacts using a local LLM (no cloud, no costs)
- **Persistent AI drafts** per enabled contact — always have a contextual message ready to send
- **Tone matching** — feeds last 20 messages of conversation history so replies sound like you
- **Service-aware routing** — iMessage in → iMessage out, SMS/RCS in → SMS out
- **Multi-handle support** — groups all of a person's numbers/emails under one contact, unified thread view
- **iCloud Contacts integration** — names instead of phone numbers
- **Privacy guardrails** — strict system-prompt rules + regex PII scrubber prevent leakage of addresses, financial info, device specs, etc.
- **iPhone remote** — embedded HTTP server with mobile web UI, QR-code pairing, token auth
- **Activity log + status indicators** — Ollama, Messages, Monitor, Server health at a glance

## Requirements

- macOS 14+
- Xcode (full IDE, not just CLI tools)
- [Ollama](https://ollama.com) running locally with `llama3.2:3b` (or any conversational model)
- Full Disk Access granted to AutoMsg.app (so it can read `~/Library/Messages/chat.db`)
- Contacts permission

## Building

```bash
cd AutoMsg
bash build.sh
open AutoMsg.app
```

The build script compiles the Swift sources, creates the .app bundle, generates the icon, and writes the Info.plist.

## Architecture

- **Sources/AutoMsg/Models** — Contact, Message, AppState
- **Sources/AutoMsg/Services** — ChatDatabaseService (chat.db reader), MessageMonitor (polling + auto-reply), OllamaService (HTTP client), MessageSender (AppleScript), ConversationContext (prompt builder + PII scrubber), ContactsResolver (iCloud Contacts), RemoteServer (HTTP API), RemoteUI (mobile web app)
- **Sources/AutoMsg/Views** — SwiftUI views (NavigationSplitView, contact list, detail with pinned draft + scrollable thread, status indicators, remote access pairing screen)
- **Sources/AutoMsg/Utilities** — SQLiteDatabase wrapper, AppleScriptRunner, Persistence (UserDefaults), QRCode generator

## Privacy

- All conversations and prompts run on your local machine; nothing is sent to third parties
- The Ollama model only sees recent thread history with the relevant contact
- A two-layer guard (prompt rules + regex scrubber) prevents the model from leaking addresses, SSNs, financial info, file paths, IP addresses, AI self-disclosure phrases, etc.

## Remote Access

The Remote Access screen runs a local HTTP server on port 8765, displays a QR code for pairing, and serves a mobile-optimized web UI for iPhone. Token-authenticated, same-WiFi only by default. Use Tailscale (or similar) for off-network access.
