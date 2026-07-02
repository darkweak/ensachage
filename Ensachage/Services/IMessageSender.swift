import Foundation
import AppKit
import CoreServices

/// Sends an iMessage by scripting the Messages app via `osascript`.
///
/// ⚠️ There is **no public API** to send iMessages; this drives Messages through
/// Apple events, which Apple has been deprecating. It therefore requires:
/// - Messages signed into the owner's iMessage account on this Mac,
/// - a one-time **Automation** permission ("control Messages"),
/// - and it may not work on the very latest macOS. Treated as best-effort.
///
/// `send` blocks until `osascript` exits, so call it off the main thread.
enum IMessageSender {

    /// Returns `nil` on success, or an error description on failure.
    @discardableResult
    static func send(text: String, attachmentPath: String?, to recipient: String) -> String? {
        let script = buildScript(text: text, attachmentPath: attachmentPath, recipient: recipient)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let errorPipe = Pipe()
        task.standardError = errorPipe
        task.standardOutput = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return error.localizedDescription
        }

        guard task.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "osascript a échoué (code \(task.terminationStatus))" : message
        }
        return nil
    }

    private static func buildScript(text: String, attachmentPath: String?, recipient: String) -> String {
        // AppleScript string literals can't contain raw newlines; flatten the body.
        let flatText = text
            .replacingOccurrences(of: "\r\n", with: " · ")
            .replacingOccurrences(of: "\n", with: " · ")

        var lines = [
            "tell application \"Messages\"",
            "set targetService to 1st service whose service type = iMessage",
            "set targetBuddy to participant \"\(escape(recipient))\" of targetService",
            "send \"\(escape(flatText))\" to targetBuddy",
        ]
        if let path = attachmentPath {
            lines.append("send (POSIX file \"\(escape(path))\") to targetBuddy")
        }
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Automation permission

    private static let messagesBundleID = "com.apple.MobileSMS"

    enum AutomationPermission {
        case authorized
        case denied
        case messagesNotRunning
        case unknown
    }

    /// Queries — and optionally prompts for — permission to control Messages via
    /// Apple events. Blocks while a prompt is on screen, so call off the main thread.
    static func automationPermission(prompt: Bool) -> AutomationPermission {
        let target = NSAppleEventDescriptor(bundleIdentifier: messagesBundleID)
        guard let desc = target.aeDesc else { return .unknown }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, prompt)
        switch status {
        case noErr:
            return .authorized
        case OSStatus(errAEEventNotPermitted):
            return .denied
        case OSStatus(procNotFound):
            return .messagesNotRunning
        default:
            return .unknown
        }
    }

    /// Launches Messages in the background (needed before the OS will show the
    /// Automation prompt, which it won't if the target app isn't running).
    static func launchMessages() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: messagesBundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        let group = DispatchGroup()
        group.enter()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in group.leave() }
        _ = group.wait(timeout: .now() + 5)
    }

    /// Ensures Messages is running, then requests permission (prompting the user).
    static func requestAutomationPermission() -> AutomationPermission {
        var result = automationPermission(prompt: true)
        if result == .messagesNotRunning {
            launchMessages()
            Thread.sleep(forTimeInterval: 1.0)
            result = automationPermission(prompt: true)
        }
        return result
    }
}
