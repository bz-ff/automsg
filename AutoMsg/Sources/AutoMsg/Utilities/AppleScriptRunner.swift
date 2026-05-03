import Foundation

enum AppleScriptRunner {
    enum SendService: String {
        case iMessage
        case sms
    }

    enum ServicePreference {
        case auto       // try iMessage first, fall back to SMS only if allowSMS is true
        case iMessage   // strict iMessage only
        case sms        // strict SMS only (force participant lookup)
    }

    @discardableResult
    static func sendMessage(text: String, to buddy: String, allowSMS: Bool = false, prefer: ServicePreference = .auto) throws -> SendService {
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBuddy = buddy
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let imessageScript = """
        tell application "Messages"
            try
                set targetService to 1st service whose service type = iMessage
                set targetBuddy to buddy "\(escapedBuddy)" of targetService
                send "\(escapedText)" to targetBuddy
                return "ok"
            on error errMsg
                return "fail:" & errMsg
            end try
        end tell
        """

        let smsScript = """
        tell application "Messages"
            try
                set smsService to first service whose service type = SMS
                set targetBuddy to buddy "\(escapedBuddy)" of smsService
                send "\(escapedText)" to targetBuddy
                return "ok"
            on error errMsg1
                try
                    send "\(escapedText)" to participant "\(escapedBuddy)"
                    return "ok"
                on error errMsg2
                    return "fail:" & errMsg1 & " | " & errMsg2
                end try
            end try
        end tell
        """

        switch prefer {
        case .sms:
            if let result = runScript(smsScript), result == "ok" {
                print("[AppleScript send] SMS (forced) -> \(buddy)")
                return .sms
            }
            throw AppleScriptError.executionFailed("SMS send failed to \(buddy). Make sure SMS forwarding from your iPhone is enabled.")

        case .iMessage:
            if let result = runScript(imessageScript), result == "ok" {
                print("[AppleScript send] iMessage (forced) -> \(buddy)")
                return .iMessage
            }
            throw AppleScriptError.executionFailed("Recipient \(buddy) is not on iMessage.")

        case .auto:
            if let result = runScript(imessageScript), result == "ok" {
                print("[AppleScript send] iMessage -> \(buddy)")
                return .iMessage
            }
            guard allowSMS else {
                throw AppleScriptError.executionFailed("Recipient \(buddy) is not on iMessage. Pick a different handle or enable SMS fallback.")
            }
            if let result = runScript(smsScript), result == "ok" {
                print("[AppleScript send] SMS (auto-fallback) -> \(buddy)")
                return .sms
            }
            throw AppleScriptError.executionFailed("Could not send to \(buddy) via iMessage or SMS")
        }
    }

    private static func runScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        let s = result.stringValue ?? ""
        return s.hasPrefix("fail:") ? nil : s
    }

    static func isMessagesRunning() -> Bool {
        let script = """
        tell application "System Events"
            return (name of processes) contains "Messages"
        end tell
        """
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return false }
        let result = appleScript.executeAndReturnError(&error)
        return error == nil && result.booleanValue
    }
}

enum AppleScriptError: Error, LocalizedError {
    case scriptCreationFailed
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptCreationFailed: return "Failed to create AppleScript"
        case .executionFailed(let msg): return "AppleScript error: \(msg)"
        }
    }
}
