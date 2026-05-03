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

## Install (end users)

Download the latest `AutoMsg.dmg` from [Releases](https://github.com/bz-ff/automsg/releases), drag AutoMsg to Applications, and launch. On first run, a setup wizard will:

1. Detect or help you install Ollama (the local AI runtime)
2. Start the Ollama service
3. Download the `llama3.2:3b` model (~2GB) with progress
4. Open System Settings panes to grant Full Disk Access, Contacts, and Local Network permissions

After setup, the wizard does not reappear.

> **Gatekeeper note**: Because this build is ad-hoc signed (no Apple Developer cert), the first launch will show "AutoMsg can't be opened because Apple cannot check it for malicious software." Right-click `AutoMsg.app` → **Open** → click **Open** in the dialog. macOS remembers this choice.

## Requirements

- macOS 14+
- ~3 GB disk (Ollama + model)
- iMessage / Messages.app set up on this Mac
- For SMS auto-reply: enable **Text Message Forwarding** on your iPhone (Settings → Messages → Text Message Forwarding → toggle on for this Mac)

## Building from source

Need the full Xcode IDE installed (not just CLI tools).

```bash
cd AutoMsg
bash build.sh                  # builds AutoMsg.app
open AutoMsg.app

# Or to package as DMG:
bash Scripts/build_dmg.sh      # produces AutoMsg.dmg
```

### Stop re-granting Full Disk Access on every rebuild

By default, `build.sh` ad-hoc signs the app — which means every rebuild produces a new code signature, so macOS treats the app as brand new and forgets your Full Disk Access / Contacts grants. To make those grants persist across rebuilds, create a stable self-signed identity once:

```bash
bash Scripts/setup_signing.sh
```

This walks you through creating a self-signed code-signing certificate via Keychain Access (one-time, ~30 seconds). After it's done, every future `build.sh` will sign with that stable identity and macOS will recognize rebuilt versions as the same app.

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
