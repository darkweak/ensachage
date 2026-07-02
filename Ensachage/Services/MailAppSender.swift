import Foundation
import AppKit
import CoreServices

/// Sends e-mail by scripting the **Apple Mail** app, using one of its already
/// configured accounts — so no SMTP host / username / password is needed.
///
/// Like iMessage, this drives Mail through Apple events and therefore needs a
/// one-time **Automation** permission ("control Mail") and Mail to have at least
/// one account set up. `send` blocks until `osascript` exits — call it off the
/// main thread.
enum MailAppSender {

    static let bundleID = "com.apple.mail"

    // MARK: - Accounts

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
        guard let output = runOSAScript(script).output else { return [] }
        var seen = Set<String>()
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - Sending

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

        let result = runOSAScript(lines.joined(separator: "\n"))
        if result.status != 0 {
            return result.error.isEmpty ? "Mail a échoué (code \(result.status))" : result.error
        }
        return nil
    }

    // MARK: - Automation permission

    enum Authorization { case authorized, denied, mailNotRunning, unknown }

    static func automationStatus(prompt: Bool) -> Authorization {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .unknown }
        switch AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, prompt) {
        case noErr: return .authorized
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .mailNotRunning
        default: return .unknown
        }
    }

    static func requestAutomationPermission() -> Authorization {
        var result = automationStatus(prompt: true)
        if result == .mailNotRunning {
            launchMail()
            Thread.sleep(forTimeInterval: 1.0)
            result = automationStatus(prompt: true)
        }
        return result
    }

    private static func launchMail() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        let group = DispatchGroup()
        group.enter()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in group.leave() }
        _ = group.wait(timeout: .now() + 5)
    }

    // MARK: - Helpers

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

    private static func runOSAScript(_ script: String) -> (status: Int32, output: String?, error: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return (-1, nil, error.localizedDescription)
        }
        let output = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let errorText = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (task.terminationStatus, output, errorText)
    }
}
