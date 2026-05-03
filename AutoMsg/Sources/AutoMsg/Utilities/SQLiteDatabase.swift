import Foundation
import SQLite3

final class SQLiteDatabase {
    private var db: OpaquePointer?
    private let path: String

    init(path: String) throws {
        self.path = path
        // SHAREDCACHE off, NOMUTEX off, full mutex on. Read-only.
        // The crucial flag here is that we will reconnect frequently to pick up writer changes.
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &db, flags, nil)
        guard result == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(db)
            throw SQLiteError.openFailed(msg)
        }
        // Force WAL checkpoint visibility — read latest committed data each query
        sqlite3_busy_timeout(db, 200)
    }

    func query(_ sql: String, params: [Any] = []) throws -> [[String: Any]] {
        var stmt: OpaquePointer?
        var result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)

        var retries = 0
        while result == SQLITE_BUSY && retries < 3 {
            Thread.sleep(forTimeInterval: 0.1)
            result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
            retries += 1
        }

        guard result == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.queryFailed(msg)
        }

        defer { sqlite3_finalize(stmt) }

        for (index, param) in params.enumerated() {
            let pos = Int32(index + 1)
            switch param {
            case let v as Int64:
                sqlite3_bind_int64(stmt, pos, v)
            case let v as Int:
                sqlite3_bind_int64(stmt, pos, Int64(v))
            case let v as String:
                sqlite3_bind_text(stmt, pos, (v as NSString).utf8String, -1, nil)
            case let v as Double:
                sqlite3_bind_double(stmt, pos, v)
            default:
                sqlite3_bind_null(stmt, pos)
            }
        }

        var rows: [[String: Any]] = []
        let colCount = sqlite3_column_count(stmt)

        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for i in 0..<colCount {
                let name = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER:
                    row[name] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT:
                    row[name] = String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_NULL:
                    row[name] = NSNull()
                default:
                    row[name] = NSNull()
                }
            }
            rows.append(row)
        }
        return rows
    }

    func close() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    deinit {
        close()
    }
}

enum SQLiteError: Error, LocalizedError {
    case openFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "SQLite open failed: \(msg)"
        case .queryFailed(let msg): return "SQLite query failed: \(msg)"
        }
    }
}
