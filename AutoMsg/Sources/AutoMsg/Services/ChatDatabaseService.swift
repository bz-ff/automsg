import Foundation

final class ChatDatabaseService {
    private let dbPath: String

    private static let coreDataEpoch: TimeInterval = 978307200

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.dbPath = "\(home)/Library/Messages/chat.db"
    }

    /// Always open a fresh connection — WAL snapshots are pinned at open time,
    /// so caching the connection means missing writes by Messages.app.
    private func ensureOpen() throws -> SQLiteDatabase {
        return try SQLiteDatabase(path: dbPath)
    }

    func fetchNewMessages(afterROWID lastROWID: Int64) throws -> [ChatMessage] {
        let database = try ensureOpen()
        let sql = """
        SELECT m.ROWID, m.text, m.date, m.is_from_me, h.id as contact_id, c.chat_identifier,
               COALESCE(m.service, h.service, '') as service,
               m.cache_has_attachments,
               (SELECT GROUP_CONCAT(att.transfer_name, ', ')
                FROM message_attachment_join maj
                LEFT JOIN attachment att ON att.ROWID = maj.attachment_id
                WHERE maj.message_id = m.ROWID) as attachment_names
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        JOIN chat c ON c.ROWID = cmj.chat_id
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        WHERE m.ROWID > ?
          AND m.is_from_me = 0
          AND c.style = 45
          AND m.associated_message_type = 0
          AND (m.text IS NOT NULL OR m.cache_has_attachments = 1)
        ORDER BY m.ROWID ASC
        """
        let rows = try database.query(sql, params: [lastROWID])
        return rows.compactMap { Self.parseMessage($0) }
    }

    func fetchConversationHistory(chatIdentifier: String, limit: Int = 20) throws -> [ChatMessage] {
        let database = try ensureOpen()
        let sql = """
        SELECT m.ROWID, m.text, m.date, m.is_from_me, h.id as contact_id, c.chat_identifier,
               COALESCE(m.service, h.service, '') as service,
               m.cache_has_attachments,
               (SELECT GROUP_CONCAT(att.transfer_name, ', ')
                FROM message_attachment_join maj
                LEFT JOIN attachment att ON att.ROWID = maj.attachment_id
                WHERE maj.message_id = m.ROWID) as attachment_names
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        JOIN chat c ON c.ROWID = cmj.chat_id
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        WHERE c.chat_identifier = ?
          AND m.associated_message_type = 0
          AND (m.text IS NOT NULL OR m.cache_has_attachments = 1)
        ORDER BY m.date DESC
        LIMIT ?
        """
        let rows = try database.query(sql, params: [chatIdentifier, limit])
        return rows.compactMap { Self.parseMessage($0) }.reversed()
    }

    func fetchAllContacts() throws -> [Contact] {
        let database = try ensureOpen()
        let sql = """
        SELECT DISTINCT h.id, h.ROWID
        FROM handle h
        JOIN chat_handle_join chj ON chj.handle_id = h.ROWID
        JOIN chat c ON c.ROWID = chj.chat_id
        WHERE c.style = 45
          AND h.service = 'iMessage'
        ORDER BY h.id
        """
        let rows = try database.query(sql)
        return rows.compactMap { row -> Contact? in
            guard let id = row["id"] as? String else { return nil }
            return Contact(id: id, displayName: id, handles: [id], isEnabled: false, currentDraft: nil)
        }
    }

    /// Returns handles where iMessage is the dominant service in the last 90 days.
    /// A handle that has any iMessage row but mostly RCS/SMS shouldn't be treated as iMessage.
    func iMessageCapableHandles() throws -> Set<String> {
        let database = try ensureOpen()
        // Compare iMessage message count vs total recent messages per handle id.
        // Threshold: iMessage must make up at least 30% of the last 90 days of activity.
        let sql = """
        WITH recent AS (
            SELECT h.id as hid, COALESCE(m.service, h.service) as svc, COUNT(*) as cnt
            FROM handle h
            JOIN message m ON m.handle_id = h.ROWID
            WHERE m.date > (strftime('%s', 'now', '-90 days') - 978307200) * 1000000000
            GROUP BY h.id, svc
        ),
        totals AS (
            SELECT hid,
                   SUM(CASE WHEN svc = 'iMessage' THEN cnt ELSE 0 END) as imessage,
                   SUM(cnt) as total
            FROM recent
            GROUP BY hid
        )
        SELECT hid FROM totals
        WHERE imessage > 0
          AND (imessage * 100 / total) >= 30
        """
        let rows = try database.query(sql)
        let handles = rows.compactMap { $0["hid"] as? String }
        return Set(handles)
    }

    /// Fetch unified history across ALL handles belonging to the same person.
    /// Accepts the contact's actual handles (phone numbers / emails) and finds every
    /// chat that includes any of them as a participant. This catches both incoming
    /// (from contact) and outgoing (to contact) messages, including SMS, RCS, iMessage.
    func fetchUnifiedHistory(forHandles handles: [String], limit: Int = 30) throws -> [ChatMessage] {
        guard !handles.isEmpty else { return [] }
        let database = try ensureOpen()

        let placeholders = Array(repeating: "?", count: handles.count).joined(separator: ",")
        let sql = """
        SELECT DISTINCT m.ROWID, m.text, m.date, m.is_from_me,
               (SELECT h2.id FROM handle h2 WHERE h2.ROWID = m.handle_id) as contact_id,
               (SELECT c2.chat_identifier FROM chat c2
                JOIN chat_message_join cmj2 ON cmj2.chat_id = c2.ROWID
                WHERE cmj2.message_id = m.ROWID LIMIT 1) as chat_identifier,
               COALESCE(m.service,
                        (SELECT h3.service FROM handle h3 WHERE h3.ROWID = m.handle_id),
                        '') as service,
               m.cache_has_attachments,
               (SELECT GROUP_CONCAT(att.transfer_name, ', ')
                FROM message_attachment_join maj
                LEFT JOIN attachment att ON att.ROWID = maj.attachment_id
                WHERE maj.message_id = m.ROWID) as attachment_names
        FROM message m
        WHERE m.ROWID IN (
            SELECT cmj.message_id
            FROM chat_message_join cmj
            JOIN chat c ON c.ROWID = cmj.chat_id
            JOIN chat_handle_join chj ON chj.chat_id = c.ROWID
            JOIN handle h ON h.ROWID = chj.handle_id
            WHERE h.id IN (\(placeholders))
              AND c.style = 45
        )
          AND m.associated_message_type = 0
          AND (m.text IS NOT NULL OR m.cache_has_attachments = 1)
        ORDER BY m.date DESC
        LIMIT ?
        """

        var params: [Any] = handles
        params.append(limit)
        let rows = try database.query(sql, params: params)
        let parsed = rows.compactMap { Self.parseMessage($0) }
        let latest = parsed.first?.date
        let latestStr = latest.map { ISO8601DateFormatter().string(from: $0) } ?? "n/a"
        print("[ChatDB] fetchUnifiedHistory(\(handles.count) handles) → \(parsed.count) msgs, latest: \(latestStr)")
        return parsed.reversed()
    }

    func findChatIdentifier(forContact contactID: String) throws -> String? {
        let database = try ensureOpen()
        let sql = """
        SELECT c.chat_identifier
        FROM chat c
        JOIN chat_handle_join chj ON chj.chat_id = c.ROWID
        JOIN handle h ON h.ROWID = chj.handle_id
        WHERE h.id = ? AND c.style = 45
        LIMIT 1
        """
        let rows = try database.query(sql, params: [contactID])
        return rows.first?["chat_identifier"] as? String
    }

    func getMaxROWID() throws -> Int64 {
        let database = try ensureOpen()
        let sql = "SELECT MAX(ROWID) as max_id FROM message"
        let rows = try database.query(sql)
        return rows.first?["max_id"] as? Int64 ?? 0
    }

    func close() {
        // No persistent connection to close — every query opens fresh
    }

    private static func parseMessage(_ row: [String: Any]) -> ChatMessage? {
        guard let rowID = row["ROWID"] as? Int64,
              let dateVal = row["date"] as? Int64,
              let isFromMeVal = row["is_from_me"] as? Int64,
              let chatIdentifier = row["chat_identifier"] as? String else {
            return nil
        }

        let text = (row["text"] as? String) ?? ""
        let contactID = (row["contact_id"] as? String) ?? ""

        let unixTime = TimeInterval(dateVal) / 1_000_000_000.0 + coreDataEpoch
        let date = Date(timeIntervalSince1970: unixTime)
        let service = (row["service"] as? String) ?? ""
        let hasAttach = ((row["cache_has_attachments"] as? Int64) ?? 0) != 0
        let attachmentNames = row["attachment_names"] as? String

        // Drop completely empty messages (no text, no attachment)
        if text.isEmpty && !hasAttach { return nil }

        return ChatMessage(
            id: rowID,
            text: text,
            isFromMe: isFromMeVal != 0,
            date: date,
            contactID: contactID,
            chatIdentifier: chatIdentifier,
            service: service,
            hasAttachment: hasAttach,
            attachmentInfo: attachmentNames
        )
    }
}
