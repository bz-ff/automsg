import SwiftUI

struct ContactDetailView: View {
    @EnvironmentObject var appState: AppState
    let contact: Contact

    @State private var messages: [ChatMessage] = []
    @State private var editableDraft: String = ""
    @State private var refreshTimer: Timer?
    @State private var isLoadingMessages: Bool = false
    @State private var lastRefreshAt: Date = Date()

    private var lastRefreshLabel: String {
        let secs = Int(Date().timeIntervalSince(lastRefreshAt))
        if secs < 5 { return "just now" }
        if secs < 60 { return "\(secs)s ago" }
        return "\(secs / 60)m ago"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            Divider()

            // Draft stays pinned at the top of the detail view (always visible)
            if contact.isEnabled {
                draftSection
                    .padding(.horizontal)
                    .padding(.top, 12)
            }

            // Pinned thread header with refresh button (does not scroll)
            HStack {
                Text("Recent Messages")
                    .font(.headline)
                    .foregroundColor(.secondary)
                if isLoadingMessages {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.leading, 4)
                }
                Spacer()
                Text(lastRefreshLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button {
                    loadMessages()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Refresh messages")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // Only the message thread scrolls (no header, no activity in scroll)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        if messages.isEmpty {
                            Text("No messages found")
                                .foregroundColor(.secondary)
                                .italic()
                                .padding(.top, 30)
                        } else {
                            ForEach(messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                        }
                        activitySection
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
                .onChange(of: messages.count) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .onAppear {
            loadData()
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
        .onChange(of: contact.id) {
            loadData()
            stopAutoRefresh()
            startAutoRefresh()
        }
        .onChange(of: contact.currentDraft) { _, newVal in
            if let draft = newVal {
                editableDraft = draft
            }
        }
        .onChange(of: appState.activityLog.count) {
            loadMessages()
        }
    }

    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        // Tighter polling — 2 seconds — so newly arrived/sent messages show up fast
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            loadMessages()
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayLabel)
                        .font(.title2.bold())
                    Text("\(contact.handles.count) handle(s)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("Enabled", isOn: Binding(
                    get: { contact.isEnabled },
                    set: { _ in appState.toggleContact(contact.id) }
                ))
                .toggleStyle(.switch)
            }

            if contact.handles.count > 0 {
                HStack(spacing: 6) {
                    Text("Send to:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: Binding(
                        get: { contact.preferredHandle ?? defaultHandle },
                        set: { newVal in appState.setPreferredHandle(newVal, for: contact.id) }
                    )) {
                        ForEach(sortedHandles, id: \.self) { handle in
                            Text(handleLabel(handle)).tag(handle)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    Toggle("Allow SMS", isOn: $appState.allowSMSFallback)
                        .toggleStyle(.checkbox)
                        .controlSize(.mini)
                        .font(.caption)
                }
            }

            if let info = appState.lastSendInfo {
                Text(info)
                    .font(.caption)
                    .foregroundColor(.green)
            }
            if let err = appState.lastSendError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var draftSection: some View {
        if contact.isEnabled {
            DraftCardView(
                draft: $editableDraft,
                isGenerating: appState.isGeneratingDraft,
                onSend: {
                    Task {
                        let sentText = editableDraft
                        if let idx = appState.contacts.firstIndex(where: { $0.id == contact.id }) {
                            appState.contacts[idx].currentDraft = editableDraft
                        }
                        await appState.sendDraft(for: contact.id)

                        // Optimistic insert so the user sees the message immediately
                        let optimistic = ChatMessage(
                            id: Int64.max - Int64(messages.count),
                            text: sentText,
                            isFromMe: true,
                            date: Date(),
                            contactID: contact.handles.first ?? "",
                            chatIdentifier: "",
                            service: "iMessage",
                            hasAttachment: false,
                            attachmentInfo: nil
                        )
                        messages.append(optimistic)

                        // Poll chat.db for the real row, replacing the optimistic one when it arrives
                        await pollUntilFound(text: sentText, deadlineSeconds: 8)
                    }
                },
                onRegenerate: {
                    Task { await appState.regenerateDraft(for: contact.id) }
                }
            )
        }
    }


    @ViewBuilder
    private var activitySection: some View {
        let contactActivity = appState.activityLog.filter { $0.contactID == contact.id }
        if !contactActivity.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Activity")
                    .font(.headline)
                    .foregroundColor(.secondary)

                ForEach(contactActivity.prefix(10)) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: entry.type == .autoReply ? "arrowshape.turn.up.left.fill" : "paperplane.fill")
                            .foregroundColor(entry.type == .autoReply ? .blue : .green)
                            .font(.caption)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.replyText)
                                .font(.callout)
                                .lineLimit(2)
                            Text(entry.timeString)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var sortedHandles: [String] {
        contact.handles.sorted { a, b in
            let aIM = appState.isIMessageCapable(a)
            let bIM = appState.isIMessageCapable(b)
            if aIM != bIM { return aIM && !bIM }
            let aEmail = a.contains("@")
            let bEmail = b.contains("@")
            if aEmail != bEmail { return aEmail && !bEmail }
            return a < b
        }
    }

    private var defaultHandle: String {
        sortedHandles.first ?? ""
    }

    private func handleLabel(_ handle: String) -> String {
        if appState.isIMessageCapable(handle) { return "✉ \(handle)  [iMessage]" }
        if handle.contains("@") { return "✉ \(handle)  [iMessage likely]" }
        return "📱 \(handle)  [SMS / RCS]"
    }

    private func loadData() {
        editableDraft = contact.currentDraft ?? ""
        loadMessages()
    }

    private func pollUntilFound(text: String, deadlineSeconds: Int) async {
        // Poll every 500ms up to deadline. Each poll opens a fresh SQLite connection
        // (ChatDatabaseService now does that), so we'll see WAL commits as they land.
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<(deadlineSeconds * 2) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !contact.handles.isEmpty,
                  let fresh = try? appState.dbService.fetchUnifiedHistory(forHandles: contact.handles, limit: 30) else {
                continue
            }
            // Check if our sent message is now in the real database
            let found = fresh.contains { $0.isFromMe && $0.text.contains(needle) && $0.date.timeIntervalSinceNow > -30 }
            messages = fresh
            if found { return }
        }
        // Fallback: ensure thread is at least refreshed even if exact match not found
        loadMessages()
    }

    private func loadMessages() {
        guard !isLoadingMessages else { return }
        isLoadingMessages = true
        let handles = contact.handles
        Task {
            defer {
                isLoadingMessages = false
                lastRefreshAt = Date()
            }
            guard !handles.isEmpty else {
                messages = []
                return
            }
            do {
                let unified = try appState.dbService.fetchUnifiedHistory(forHandles: handles, limit: 30)
                messages = unified
            } catch {
                print("[ContactDetailView] loadMessages error: \(error)")
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    private var timeString: String {
        let f = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(message.date) {
            f.dateFormat = "h:mm a"
        } else if cal.isDateInYesterday(message.date) {
            return "Yesterday " + {
                let g = DateFormatter(); g.dateFormat = "h:mm a"; return g.string(from: message.date)
            }()
        } else {
            f.dateFormat = "MMM d, h:mm a"
        }
        return f.string(from: message.date)
    }

    var body: some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
            HStack(alignment: .bottom) {
                if message.isFromMe { Spacer(minLength: 40) }

                VStack(alignment: .leading, spacing: 4) {
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.callout)
                            .foregroundColor(message.isFromMe ? .white : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if message.hasAttachment {
                        HStack(spacing: 4) {
                            Image(systemName: "paperclip")
                                .font(.caption)
                            Text(message.attachmentInfo ?? "attachment")
                                .font(.caption)
                                .italic()
                        }
                        .foregroundColor(message.isFromMe ? .white.opacity(0.85) : .secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(message.isFromMe ? Color.blue : Color.gray.opacity(0.25))
                .cornerRadius(14)

                if !message.isFromMe { Spacer(minLength: 40) }
            }
            Text(timeString)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: message.isFromMe ? .trailing : .leading)
        }
        .padding(.bottom, 4)
    }
}
