import Foundation
import AppKit
import CoreServices

/// Sends e-mail by scripting **Apple Mail** using one of its configured accounts
/// — no SMTP host / username / password needed.
///
/// The AppleScript runs **in-process** via `NSAppleScript` (not a spawned
/// `osascript`) so the Apple events are attributed to Ensachage: the app that
/// holds the `com.apple.security.automation.apple-events` entitlement, the
/// `NSAppleEventsUsageDescription`, and the TCC Automation grant. Sending through
/// a child `osascript` process instead attributes the events to `osascript`,
/// which breaks the permission.
///
/// `NSAppleScript` must run on the main thread, hence `@MainActor`.
@MainActor
enum MailAppSender {

    nonisolated static let bundleID = "com.apple.mail"

    /// Returns the sender addresses of every account configured in Mail.
    static func senderAddresses() -> [String] {
        let script = """
        tell application "Mail"
            set addrList to {}
            repeat with acc in accounts
                try
                    set addrList to addrList & (email addresses of acc)
                end try
            end repeat
            set AppleScript's text item delimiters to linefeed
            set out to addrList as text
        end tell
        return out
        """
        guard let output = run(script).output else { return [] }
        var seen = Set<String>()
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Returns `nil` on success, or an error description on failure.
    @discardableResult
    static func send(subject: String, body: String, attachmentPath: String?, from: String, to: String) -> String? {
        var lines = [
            "tell application \"Mail\"",
            "set newMessage to make new outgoing message with properties {subject:\(expr(subject)), content:\(expr(body)), visible:false}",
            "tell newMessage",
        ]
        if !from.isEmpty {
            lines.append("set sender to \(expr(from))")
        }
        lines.append("make new to recipient at end of to recipients with properties {address:\(expr(to))}")
        if let path = attachmentPath {
            lines.append("tell content")
            lines.append("make new attachment with properties {file name:(POSIX file \(expr(path)))} at after the last paragraph")
            lines.append("end tell")
            lines.append("delay 1") // give Mail time to attach before sending
        }
        lines.append("end tell")
        lines.append("send newMessage")
        lines.append("end tell")
        return run(lines.joined(separator: "\n")).error
    }

    // MARK: - Automation permission (thread-agnostic Apple-event checks)

    enum Authorization { case authorized, denied, mailNotRunning, unknown }

    nonisolated static func automationStatus(prompt: Bool) -> Authorization {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .unknown }
        switch AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, prompt) {
        case noErr: return .authorized
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .mailNotRunning
        default: return .unknown
        }
    }

    nonisolated static func requestAutomationPermission() -> Authorization {
        var result = automationStatus(prompt: true)
        if result == .mailNotRunning {
            launchMail()
            Thread.sleep(forTimeInterval: 1.0)
            result = automationStatus(prompt: true)
        }
        return result
    }

    nonisolated private static func launchMail() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        let group = DispatchGroup()
        group.enter()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in group.leave() }
        _ = group.wait(timeout: .now() + 5)
    }

    // MARK: - Helpers

    private static func run(_ source: String) -> (output: String?, error: String?) {
        var errorDict: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return (nil, "Script AppleScript invalide")
        }
        let result = script.executeAndReturnError(&errorDict)
        if let errorDict {
            let message = (errorDict[NSAppleScript.errorMessage] as? String) ?? "\(errorDict)"
            return (nil, message)
        }
        return (result.stringValue, nil)
    }

    /// AppleScript string expression, preserving line breaks via `& linefeed &`.
    private static func expr(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return escaped
            .components(separatedBy: "\n")
            .map { "\"\($0)\"" }
            .joined(separator: " & linefeed & ")
    }
}
