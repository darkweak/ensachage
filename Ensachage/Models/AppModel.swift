import SwiftUI
import AppKit
import Observation
import ServiceManagement

/// Central coordinator injected into the view hierarchy. Owns settings, the
/// journal store, the camera and the lock monitor, and exposes the high-level
/// behaviour so the views stay free of business logic.
@MainActor
@Observable
final class AppModel {

    let settings: AppSettings
    let history: LogStore

    private(set) var cameraAuthorized: Bool
    private(set) var isMonitoring = false

    /// True when camera access was explicitly denied (must be re-enabled in System Settings).
    var cameraDenied: Bool { camera.authorizationStatus == .denied }

    /// Set on first launch so the UI can present itself once after the prompt.
    private(set) var openJournalAtLaunch = false

    @ObservationIgnored private let camera = CameraCapture.shared
    @ObservationIgnored private let monitor = LockMonitor()
    @ObservationIgnored private var didStart = false

    init() {
        self.settings = AppSettings()
        self.history = LogStore()
        self.cameraAuthorized = CameraCapture.shared.authorizationStatus == .authorized
    }

    // MARK: - Launch

    /// Runs once at launch: requests camera permission on first launch, then
    /// starts monitoring according to the saved settings.
    func bootstrap() async {
        guard !didStart else { return }
        didStart = true

        // Ask for camera permission whenever it hasn't been decided yet — at the
        // first launch, but also after a permissions reset. The system prompt
        // only appears while the status is `notDetermined`.
        if camera.authorizationStatus == .notDetermined {
            _ = await requestCameraAccess()
        } else {
            cameraAuthorized = camera.authorizationStatus == .authorized
        }

        if !settings.hasCompletedOnboarding {
            settings.hasCompletedOnboarding = true
            openJournalAtLaunch = true
        }

        applyLaunchAtLogin()
        setMonitoring(settings.monitoringEnabled)
    }

    // MARK: - Camera

    /// Requests camera access. The system prompt only appears when the status is
    /// `notDetermined`; if it was already denied we can't re-prompt, so we open
    /// the Camera privacy pane in System Settings instead.
    @discardableResult
    func requestCameraAccess() async -> Bool {
        switch camera.authorizationStatus {
        case .authorized:
            cameraAuthorized = true
            return true
        case .notDetermined:
            let granted = await camera.requestAccess()
            cameraAuthorized = granted
            return granted
        case .denied:
            cameraAuthorized = false
            openCameraPrivacySettings()
            return false
        }
    }

    /// Opens System Settings ▸ Privacy & Security ▸ Camera.
    func openCameraPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Manually capture a frame (used by the "test" action) to confirm the camera works.
    func captureTest() {
        Task {
            let data = await camera.captureSnapshot()
            cameraAuthorized = camera.authorizationStatus == .authorized
            history.record(outcome: .test, imageData: data)
        }
    }

    // MARK: - Monitoring

    func setMonitoring(_ on: Bool) {
        settings.monitoringEnabled = on
        if on {
            monitor.predicate = settings.failurePredicate
            monitor.onIntrusion = { [weak self] in self?.handleIntrusion() }
            monitor.onUnlock = { [weak self] in self?.handleUnlock() }
            monitor.start()
        } else {
            monitor.stop()
        }
        isMonitoring = monitor.isRunning
    }

    private func handleIntrusion() {
        Task {
            var data: Data?
            if settings.captureOnFailure {
                data = await camera.captureSnapshot()
            }
            cameraAuthorized = camera.authorizationStatus == .authorized
            let entry = history.record(outcome: .failure, imageData: data)
            notifyOwner(for: entry, imageData: data)
            messageOwner(for: entry)
        }
    }

    private func handleUnlock() {
        history.record(outcome: .success, imageData: nil)
    }

    // MARK: - Login item

    func applyLaunchAtLogin() {
        setLaunchAtLogin(settings.launchAtLogin)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Registration can fail in development (unsigned / not in /Applications).
            // The saved preference is kept; it takes effect once the app is installed.
        }
    }

    // MARK: - Dock icon visibility

    /// Shows the Dock icon while a real window (journal / settings) is open, and
    /// hides it (menu-bar-only agent) when none remain. Driven by `NSWindow`
    /// notifications from the app delegate, so it stays in sync regardless of
    /// SwiftUI view lifecycle quirks.
    func refreshDockVisibility() {
        let hasRealWindow = NSApp.windows.contains { window in
            window.isVisible && window.styleMask.contains(.titled)
        }
        let policy: NSApplication.ActivationPolicy = hasRealWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular {
            // Agent apps promoted to .regular otherwise show a blank/generic Dock
            // icon, so set the bundle icon explicitly.
            if let icon = Self.bundleIcon() {
                NSApp.applicationIconImage = icon
            }
            NSApp.activate()
        }
    }

    private static func bundleIcon() -> NSImage? {
        if let named = NSImage(named: "AppIcon") { return named }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        let path = Bundle.main.bundlePath
        let workspaceIcon = NSWorkspace.shared.icon(forFile: path)
        return workspaceIcon.size.width > 0 ? workspaceIcon : nil
    }

    // MARK: - Sharing

    /// A human-readable summary of an entry, used as the message / e-mail body.
    func shareSummary(for entry: LogEntry) -> String {
        let when = entry.date.formatted(date: .complete, time: .standard)
        return """
        Ensachage 🍏 — \(entry.outcome.title)
        \(when)

        Une tentative d'accès a été enregistrée sur votre Mac.
        """
    }

    /// Opens a pre-addressed e-mail to the configured owner with the photo
    /// attached. Falls back to a `mailto:` compose window if Mail can't perform
    /// the share service (e.g. no configured account).
    func emailToOwner(for entry: LogEntry) {
        let email = settings.ownerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = "Ensachage 🍏 — \(entry.outcome.title)"
        let body = shareSummary(for: entry)

        if let service = NSSharingService(named: .composeEmail) {
            service.recipients = email.isEmpty ? nil : [email]
            service.subject = subject
            var items: [Any] = [body]
            if let url = history.imageURL(for: entry) { items.append(url) }
            if service.canPerform(withItems: items) {
                service.perform(withItems: items)
                return
            }
        }

        // Fallback: open the default mail client (no attachment possible via mailto).
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = email
        comps.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = comps.url {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Automatic e-mail notification (SMTP)

    /// Builds an SMTP config from settings + Keychain, or `nil` if incomplete.
    func smtpConfig() -> SMTPConfig? {
        let host = settings.smtpHost.trimmingCharacters(in: .whitespaces)
        let user = settings.smtpUsername.trimmingCharacters(in: .whitespaces)
        let to = settings.ownerEmail.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !user.isEmpty, !to.isEmpty,
              let password = settings.smtpPassword, !password.isEmpty else { return nil }
        let from = settings.smtpFrom.trimmingCharacters(in: .whitespaces)
        return SMTPConfig(
            host: host,
            port: UInt16(clamping: settings.smtpPort),
            username: user,
            password: password,
            from: from.isEmpty ? user : from,
            to: to
        )
    }

    /// Fire-and-forget background e-mail to the owner (works while locked).
    func notifyOwner(for entry: LogEntry, imageData: Data?) {
        guard settings.autoNotifyOwner else { return }
        let subject = "Ensachage 🍏 — \(entry.outcome.title)"
        let body = shareSummary(for: entry)

        switch settings.emailMethod {
        case .smtp:
            guard let config = smtpConfig() else { return }
            let message = SMTPMessage(
                subject: subject,
                body: body,
                attachment: imageData.map {
                    SMTPAttachment(filename: "ensachage.jpg", mimeType: "image/jpeg", data: $0)
                }
            )
            Task.detached { try? await SMTPClient.send(message, config: config) }

        case .appleMail:
            let to = settings.ownerEmail.trimmingCharacters(in: .whitespaces)
            guard !to.isEmpty else { return }
            let from = settings.mailSenderAddress.trimmingCharacters(in: .whitespaces)
            let path = history.imageURL(for: entry)?.path
            Task.detached {
                MailAppSender.send(subject: subject, body: body, attachmentPath: path, from: from, to: to)
            }
        }
    }

    /// Sends a test e-mail and returns a human-readable result for the UI.
    func sendTestEmail() async -> String {
        let subject = "Ensachage 🍏 — test"
        let body = "Ceci est un e-mail de test envoyé par Ensachage. La notification automatique est correctement configurée."

        switch settings.emailMethod {
        case .smtp:
            guard let config = smtpConfig() else {
                return "Configuration incomplète : serveur, utilisateur, mot de passe et e-mail du propriétaire sont requis."
            }
            let message = SMTPMessage(subject: subject, body: body, attachment: nil)
            do {
                try await SMTPClient.send(message, config: config)
                return "✓ E-mail de test envoyé à \(config.to)."
            } catch {
                return "✗ Échec : \(error.localizedDescription)"
            }

        case .appleMail:
            let to = settings.ownerEmail.trimmingCharacters(in: .whitespaces)
            guard !to.isEmpty else {
                return "Définissez l'e-mail du propriétaire (onglet Général) avant d'envoyer un test."
            }
            let from = settings.mailSenderAddress.trimmingCharacters(in: .whitespaces)
            let result = await Task.detached {
                MailAppSender.send(subject: subject, body: body, attachmentPath: nil, from: from, to: to)
            }.value
            if let error = result { return "✗ Échec : \(error)" }
            return "✓ E-mail de test envoyé à \(to) via Apple Mail."
        }
    }

    /// Selects the e-mail method. Choosing Apple Mail requests the Mail
    /// Automation permission now (while unlocked) and returns a status string.
    @discardableResult
    func setEmailMethod(_ method: AppSettings.EmailMethod) async -> String {
        settings.emailMethod = method
        guard method == .appleMail else { return "" }
        let permission = await Task.detached { MailAppSender.requestAutomationPermission() }.value
        switch permission {
        case .authorized:  return "✓ Autorisation accordée : Ensachage peut utiliser Apple Mail."
        case .denied:      return "✗ Autorisation refusée. Activez Ensachage → Mail dans Réglages système ▸ Confidentialité et sécurité ▸ Automatisation."
        case .mailNotRunning: return "Ouvrez l'app Mail puis réessayez."
        case .unknown:     return "Statut d'autorisation indéterminé — envoyez un e-mail de test pour vérifier."
        }
    }

    /// Fetches the sender addresses configured in Apple Mail (best-effort).
    func mailSenderAddresses() async -> [String] {
        await Task.detached { MailAppSender.senderAddresses() }.value
    }

    // MARK: - Automatic iMessage notification

    /// Enables/disables iMessage alerts. Enabling first requests the Messages
    /// Automation permission (so the prompt appears now, while unlocked, rather
    /// than on a later locked-screen failure where it couldn't be answered).
    /// Returns a human-readable status; the toggle stays off if permission is denied.
    @discardableResult
    func setIMessageEnabled(_ enabled: Bool) async -> String {
        guard enabled else {
            settings.autoIMessageOwner = false
            return ""
        }
        let permission = await Task.detached { IMessageSender.requestAutomationPermission() }.value
        switch permission {
        case .authorized:
            settings.autoIMessageOwner = true
            return "✓ Autorisation accordée : Ensachage peut contrôler Messages."
        case .denied:
            settings.autoIMessageOwner = false
            return "✗ Autorisation refusée. Activez Ensachage → Messages dans Réglages système ▸ Confidentialité et sécurité ▸ Automatisation, puis réessayez."
        case .messagesNotRunning:
            settings.autoIMessageOwner = false
            return "Impossible de lancer Messages. Ouvrez l'app Messages puis réessayez."
        case .unknown:
            settings.autoIMessageOwner = true
            return "Statut d'autorisation indéterminé — envoyez un iMessage de test pour vérifier."
        }
    }

    /// Fire-and-forget iMessage to the owner (best-effort; scripts Messages.app).
    func messageOwner(for entry: LogEntry) {
        guard settings.autoIMessageOwner else { return }
        let phone = settings.ownerPhone.trimmingCharacters(in: .whitespaces)
        guard !phone.isEmpty else { return }
        let text = shareSummary(for: entry)
        let attachment = history.imageURL(for: entry)?.path
        Task.detached {
            IMessageSender.send(text: text, attachmentPath: attachment, to: phone)
        }
    }

    /// Sends a test iMessage and returns a human-readable result for the UI.
    func sendTestIMessage() async -> String {
        let phone = settings.ownerPhone.trimmingCharacters(in: .whitespaces)
        guard !phone.isEmpty else {
            return "Numéro / identifiant iMessage du propriétaire manquant."
        }
        let result = await Task.detached {
            IMessageSender.send(
                text: "Ensachage 🍏 — iMessage de test. Les alertes sont bien configurées.",
                attachmentPath: nil,
                to: phone
            )
        }.value
        if let error = result {
            return "✗ Échec : \(error)"
        }
        return "✓ iMessage de test envoyé à \(phone)."
    }
}
