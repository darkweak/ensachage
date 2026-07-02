import Foundation

/// A single record in the login journal.
struct LogEntry: Identifiable, Codable, Hashable {

    enum Outcome: String, Codable {
        /// A successful unlock of the macOS lock screen.
        case success
        /// A failed unlock attempt (wrong password at the lock screen).
        case failure
        /// A manual test capture triggered from the app.
        case test
    }

    let id: UUID
    let date: Date
    let outcome: Outcome
    /// File name (relative to the images directory) of the intruder photo, if one was captured.
    var imageFileName: String?

    init(id: UUID = UUID(), date: Date, outcome: Outcome, imageFileName: String? = nil) {
        self.id = id
        self.date = date
        self.outcome = outcome
        self.imageFileName = imageFileName
    }
}
