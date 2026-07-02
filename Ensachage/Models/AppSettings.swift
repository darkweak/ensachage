import Foundation
import Observation

/// User-configurable settings, transparently persisted to `UserDefaults`.
///
/// Every stored property writes itself back through a `didSet` observer, so any
/// mutation — whether from a SwiftUI control binding or from code — is saved
/// immediately and survives relaunches (values are reloaded in `init`).
@Observable
final class AppSettings {

    private enum Keys {
        static let onboarding = "hasCompletedOnboarding"
        static let monitoring = "monitoringEnabled"
        static let captureOnFailure = "captureOnFailure"
        static let launchAtLogin = "launchAtLogin"
        static let predicate = "failurePredicate"
        static let predicateVersion = "failurePredicateVersion"
        static let ownerEmail = "ownerEmail"
        static let autoNotifyOwner = "autoNotifyOwner"
        static let smtpHost = "smtpHost"
        static let smtpPort = "smtpPort"
        static let smtpUsername = "smtpUsername"
        static let smtpFrom = "smtpFrom"
        static let ownerPhone = "ownerPhone"
        static let autoIMessageOwner = "autoIMessageOwner"
        static let emailMethod = "emailMethod"
        static let mailSenderAddress = "mailSenderAddress"
    }

    /// How automatic e-mails are sent.
    enum EmailMethod: String, CaseIterable, Identifiable {
        case smtp        // direct SMTP-over-TLS with stored credentials
        case appleMail   // script the Apple Mail app using a configured account
        var id: String { rawValue }
    }

    /// Keychain coordinates for the SMTP password.
    static let smtpKeychainService = "com.darkweak.ensachage.smtp"
    private static let smtpKeychainAccount = "password"

    /// Bumped whenever the built-in default predicate changes, so a previously
    /// saved (now-stale) predicate is migrated instead of overriding the fix.
    private static let currentPredicateVersion = 3

    /// Whether the first-launch camera-permission prompt has been shown.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }

    /// Master switch for lock-screen monitoring. Default: on.
    var monitoringEnabled: Bool {
        didSet { defaults.set(monitoringEnabled, forKey: Keys.monitoring) }
    }

    /// Capture a webcam photo on each failed unlock. Default: on.
    var captureOnFailure: Bool {
        didSet { defaults.set(captureOnFailure, forKey: Keys.captureOnFailure) }
    }

    /// Whether the app is registered as a login item. Default: off.
    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    /// The `log stream` predicate used to detect unlock failures (tunable per OS).
    var failurePredicate: String {
        didSet { defaults.set(failurePredicate, forKey: Keys.predicate) }
    }

    /// E-mail address of the laptop owner, used by "send to owner". Default: empty.
    var ownerEmail: String {
        didSet { defaults.set(ownerEmail, forKey: Keys.ownerEmail) }
    }

    /// Automatically e-mail the owner on each failed unlock. Default: off.
    var autoNotifyOwner: Bool {
        didSet { defaults.set(autoNotifyOwner, forKey: Keys.autoNotifyOwner) }
    }

    /// Whether automatic e-mail uses direct SMTP or the Apple Mail app.
    var emailMethod: EmailMethod {
        didSet { defaults.set(emailMethod.rawValue, forKey: Keys.emailMethod) }
    }

    /// The Apple Mail sender address to send from (must be a configured account).
    var mailSenderAddress: String {
        didSet { defaults.set(mailSenderAddress, forKey: Keys.mailSenderAddress) }
    }

    /// Owner's phone number / iMessage address for automatic iMessage alerts.
    var ownerPhone: String {
        didSet { defaults.set(ownerPhone, forKey: Keys.ownerPhone) }
    }

    /// Automatically send an iMessage to the owner on each failed unlock. Default: off.
    var autoIMessageOwner: Bool {
        didSet { defaults.set(autoIMessageOwner, forKey: Keys.autoIMessageOwner) }
    }

    var smtpHost: String {
        didSet { defaults.set(smtpHost, forKey: Keys.smtpHost) }
    }
    var smtpPort: Int {
        didSet { defaults.set(smtpPort, forKey: Keys.smtpPort) }
    }
    var smtpUsername: String {
        didSet { defaults.set(smtpUsername, forKey: Keys.smtpUsername) }
    }
    /// Sender address. Empty → the username is used.
    var smtpFrom: String {
        didSet { defaults.set(smtpFrom, forKey: Keys.smtpFrom) }
    }

    /// SMTP password, stored in the Keychain (not in UserDefaults).
    var smtpPassword: String? {
        get { Keychain.get(service: Self.smtpKeychainService, account: Self.smtpKeychainAccount) }
        set { Keychain.set(newValue, service: Self.smtpKeychainService, account: Self.smtpKeychainAccount) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Property observers do not fire during initialization, so these direct
        // assignments load saved values without redundantly writing them back.
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        self.monitoringEnabled = defaults.object(forKey: Keys.monitoring) as? Bool ?? true
        self.captureOnFailure = defaults.object(forKey: Keys.captureOnFailure) as? Bool ?? true
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.ownerEmail = defaults.string(forKey: Keys.ownerEmail) ?? ""
        self.autoNotifyOwner = defaults.bool(forKey: Keys.autoNotifyOwner)
        self.smtpHost = defaults.string(forKey: Keys.smtpHost) ?? ""
        self.smtpPort = defaults.object(forKey: Keys.smtpPort) as? Int ?? 465
        self.smtpUsername = defaults.string(forKey: Keys.smtpUsername) ?? ""
        self.smtpFrom = defaults.string(forKey: Keys.smtpFrom) ?? ""
        self.ownerPhone = defaults.string(forKey: Keys.ownerPhone) ?? ""
        self.autoIMessageOwner = defaults.bool(forKey: Keys.autoIMessageOwner)
        self.emailMethod = EmailMethod(rawValue: defaults.string(forKey: Keys.emailMethod) ?? "") ?? .appleMail
        self.mailSenderAddress = defaults.string(forKey: Keys.mailSenderAddress) ?? ""

        // Migrate a stale saved predicate to the current built-in default.
        let savedVersion = defaults.integer(forKey: Keys.predicateVersion)
        if savedVersion < Self.currentPredicateVersion {
            self.failurePredicate = LockMonitor.defaultPredicate
            defaults.set(LockMonitor.defaultPredicate, forKey: Keys.predicate)
            defaults.set(Self.currentPredicateVersion, forKey: Keys.predicateVersion)
        } else {
            self.failurePredicate = defaults.string(forKey: Keys.predicate) ?? LockMonitor.defaultPredicate
        }
    }

    /// Restores the detection predicate to the safe default (password only).
    func resetPredicate() {
        failurePredicate = LockMonitor.defaultPredicate
    }

    /// Opts into the experimental predicate that also matches fingerprint / PIN.
    func useExtendedPredicate() {
        failurePredicate = LockMonitor.extendedPredicate
    }
}
