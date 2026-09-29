import Foundation

/// Where the app keeps its own files.
enum AppFolders {
    /// ~/Library/Application Support/Deduplicator
    static let support = URL.applicationSupportDirectory.appending(path: "Deduplicator", directoryHint: .isDirectory)

    static let scanCache = support.appending(path: "ScanCache.json")
}
