import Foundation
import Observation

/// Persists the login journal (`history.json`) and the captured intruder photos
/// (`Images/<uuid>.jpg`) inside the app's Application Support directory.
///
/// `@Observable` so SwiftUI views refresh automatically when `entries` changes.
@Observable
final class LogStore {

    /// Newest entry first.
    private(set) var entries: [LogEntry] = []

    @ObservationIgnored private let fileManager = FileManager.default

    @ObservationIgnored private lazy var baseURL: URL = {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Ensachage", isDirectory: true)
    }()

    @ObservationIgnored private lazy var entriesURL = baseURL.appendingPathComponent("history.json")
    @ObservationIgnored private lazy var imagesURL = baseURL.appendingPathComponent("Images", isDirectory: true)

    init() {
        createDirectories()
        load()
    }

    // MARK: - Recording

    /// Appends a new journal entry. If `imageData` is provided it is written to
    /// disk and referenced from the entry. Returns the created entry.
    @discardableResult
    func record(outcome: LogEntry.Outcome, imageData: Data?) -> LogEntry {
        var fileName: String?
        if let imageData {
            let name = UUID().uuidString + ".jpg"
            do {
                try imageData.write(to: imagesURL.appendingPathComponent(name))
                fileName = name
            } catch {
                fileName = nil
            }
        }
        let entry = LogEntry(date: Date(), outcome: outcome, imageFileName: fileName)
        entries.insert(entry, at: 0)
        save()
        return entry
    }

    /// Resolves the on-disk URL of an entry's photo, if it exists.
    func imageURL(for entry: LogEntry) -> URL? {
        guard let name = entry.imageFileName else { return nil }
        let url = imagesURL.appendingPathComponent(name)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Removes every entry and its associated photo.
    func clear() {
        entries.removeAll()
        try? fileManager.removeItem(at: imagesURL)
        createDirectories()
        save()
    }

    // MARK: - Persistence

    private func createDirectories() {
        try? fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true)
    }

    private func load() {
        guard let data = try? Data(contentsOf: entriesURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([LogEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: entriesURL, options: .atomic)
    }
}
