import Foundation

/// Where the app keeps its own files.
enum AppFolders {
    /// ~/Library/Application Support/Deduplicator
    static let support = URL.applicationSupportDirectory.appending(path: "Deduplicator", directoryHint: .isDirectory)

    static let scanCache = support.appending(path: "ScanCache.json")

    /// Every removal, and whether it was undone.
    static let removalLog = support.appending(path: "RemovalLog.json")

    /// ~/Library/Caches/Deduplicator/Waveforms. The system may empty it, which
    /// only means waveforms are drawn again.
    static let waveforms = URL.cachesDirectory.appending(path: "Deduplicator/Waveforms", directoryHint: .isDirectory)
}
