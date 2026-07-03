import Foundation
import AppKit
import CoreServices

/// Sends an iMessage by scripting the Messages app via **in-process** Apple
/// events (`NSAppleScript`), so the events are attributed to Ensachage (which
/// holds the apple-events entitlement, usage description and TCC grant) rather
/// than to a spawned `osascript` process.
///
/// ⚠️ There is no public API to send iMessages; this drives Messages through
/// Apple events, which Apple has been deprecating. It requires Messages signed
/// into the owner's account, the Automation permission, and may not work on the
/// very latest macOS. Best-effort. `NSAppleScript` must run on the main thread.
@MainActor
enum IMessageSender {

    nonisolated static let bundleID = "com.apple.MobileSMS"

    /// Returns `nil` on success, or an error description on failure.
    @discardableResult
    static func send(text: String, attachmentPath: String?, to recipient: String) -> String? {
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
        return run(lines.joined(separator: "\n")).error
    }

    // MARK: - Automation permission (thread-agnostic Apple-event checks)

    enum AutomationPermission { case authorized, denied, messagesNotRunning, unknown }

    nonisolated static func automationPermission(prompt: Bool) -> AutomationPermission {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .unknown }
        switch AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, prompt) {
        case noErr: return .authorized
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .messagesNotRunning
        default: return .unknown
        }
    }

    nonisolated static func requestAutomationPermission() -> AutomationPermission {
        var result = automationPermission(prompt: true)
        if result == .messagesNotRunning {
            launchMessages()
            Thread.sleep(forTimeInterval: 1.0)
            result = automationPermission(prompt: true)
        }
        return result
    }

    nonisolated private static func launchMessages() {
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

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
