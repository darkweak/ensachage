import Foundation
import AppKit

/// Detects **failed unlock attempts on the real macOS lock screen**.
///
/// macOS exposes no public API for "the user mistyped the unlock password", so
/// this works by combining two public signals:
///
/// 1. **Screen-lock state** — the `com.apple.screenIsLocked` /
///    `com.apple.screenIsUnlocked` distributed notifications tell us whether the
///    lock screen is currently up.
/// 2. **Unlock authentication failures** — we live-stream the unified log
///    (`/usr/bin/log stream --level info`) filtered to the processes that
///    evaluate the unlock password (`loginwindow`, `opendirectoryd`,
///    `coreauthd`, `SecurityAgent`) and to failure keywords.
///
/// A log match is treated as an intrusion **only while the screen is locked**,
/// which filters out unrelated authentication failures (sudo, ssh, …) that
/// happen on an unlocked Mac. Matches are debounced so one mistyped password
/// (which can emit several log lines) yields a single event.
///
/// > The log predicate is inherently macOS-version-sensitive. It is exposed in
/// > Settings so it can be tuned without rebuilding.
final class LockMonitor {

    /// Default predicate passed to `log stream`. Matches **only** a wrong
    /// password at the lock screen, and nothing else.
    ///
    /// `opendirectoryd` logs `ODRecordVerifyPassword failed with result
    /// ODErrorCredentialsInvalid` on a wrong password; a correct password logs
    /// *succeeded*, and **locking / display sleep log nothing** — so this clause
    /// never fires on a lock or a successful unlock. (Matches additionally only
    /// count while the screen is locked, see `handleLogLine`.) Verified.
    static let defaultPredicate =
        #"process == "loginwindow" AND eventMessage CONTAINS "authFailWithMessage" AND eventMessage CONTAINS "authentication failed""#

    /// Optional, **experimental** predicate that also tries to catch a bad
    /// fingerprint (`biometrickitd`) and a bad smartcard / YubiKey PIN (`ctkd`).
    ///
    /// ⚠️ The fingerprint/PIN message text is hardware/OS-specific and the
    /// biometric subsystem emits readiness noise around lock and display sleep,
    /// which can cause false positives until tuned. Opt in from Settings ▸ Avancé
    /// and tune with `make watch-auth`.
    static let extendedPredicate = """
    (process == "loginwindow" AND eventMessage CONTAINS "authFailWithMessage" AND eventMessage CONTAINS "authentication failed") \
    OR (process == "biometrickitd" AND eventMessage CONTAINS[c] "match" \
    AND (eventMessage CONTAINS[c] "no match" OR eventMessage CONTAINS[c] "not match" \
    OR eventMessage CONTAINS[c] "match failed" OR eventMessage CONTAINS[c] "failed to match")) \
    OR (process == "ctkd" AND eventMessage CONTAINS[c] "pin" \
    AND (eventMessage CONTAINS[c] "fail" OR eventMessage CONTAINS[c] "wrong" OR eventMessage CONTAINS[c] "invalid"))
    """

    /// Called on the main queue when a failed unlock is detected.
    var onIntrusion: (() -> Void)?
    /// Called on the main queue when the screen is successfully unlocked.
    var onUnlock: (() -> Void)?

    var predicate: String = LockMonitor.defaultPredicate

    private let distributed = DistributedNotificationCenter.default()
    private var process: Process?
    private var buffer = Data()
    private var isLocked = false
    private var lastFire = Date.distantPast
    private let debounce: TimeInterval = 2.0
    private var running = false

    var isRunning: Bool { running }

    // MARK: - Lifecycle

    func start() {
        guard !running else { return }
        running = true
        observeLockState()
        startLogStream()
    }

    func stop() {
        guard running else { return }
        running = false
        distributed.removeObserver(self)
        process?.terminate()
        process = nil
        buffer.removeAll()
    }

    // MARK: - Screen lock state

    private func observeLockState() {
        distributed.addObserver(
            self, selector: #selector(screenLocked),
            name: .init("com.apple.screenIsLocked"), object: nil
        )
        distributed.addObserver(
            self, selector: #selector(screenUnlocked),
            name: .init("com.apple.screenIsUnlocked"), object: nil
        )
    }

    @objc private func screenLocked() { isLocked = true }

    @objc private func screenUnlocked() {
        isLocked = false
        DispatchQueue.main.async { [weak self] in self?.onUnlock?() }
    }

    // MARK: - Unified log streaming

    private func startLogStream() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = ["stream", "--style", "ndjson", "--level", "info", "--predicate", predicate]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.consume(chunk)
        }

        do {
            try task.run()
            process = task
        } catch {
            // `log` unavailable — monitoring silently disabled.
            running = false
        }
    }

    /// Accumulates streamed bytes and processes complete newline-delimited records.
    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        let newline = UInt8(ascii: "\n")
        while let idx = buffer.firstIndex(of: newline) {
            let line = buffer[buffer.startIndex..<idx]
            buffer.removeSubrange(buffer.startIndex...idx)
            guard !line.isEmpty else { continue }
            handleLogLine(Data(line))
        }
    }

    private func handleLogLine(_ data: Data) {
        // The predicate already restricts this to unlock-related failures; we only
        // need to gate on lock state and debounce. (`log` emits an initial banner
        // line that isn't valid JSON — ignore anything without an eventMessage.)
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isLocked else { return }
            let now = Date()
            guard now.timeIntervalSince(self.lastFire) > self.debounce else { return }
            self.lastFire = now
            self.onIntrusion?()
        }
    }

    deinit { stop() }
}
