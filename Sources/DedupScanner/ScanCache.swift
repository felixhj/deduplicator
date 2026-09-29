import DedupCore
import Foundation

/// Tracks read in earlier scans, keyed by path and checked against file size
/// and modification date, so a rescan only reads files that changed.
public struct ScanCache: Sendable {
    struct Entry: Codable, Sendable, Hashable {
        var size: Int64
        var modified: Date
        var track: Track
    }

    /// Bump when readers start storing something different in a `Track`, so
    /// entries written by older code are read again.
    static let version = 1

    private(set) var entries: [String: Entry] = [:]

    public init() {}

    public var count: Int { entries.count }

    /// Returns an empty cache when the file is missing, unreadable or from another version.
    public static func load(from url: URL) -> ScanCache {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(CacheFile.self, from: data),
              file.version == version
        else { return ScanCache() }
        var cache = ScanCache()
        cache.entries = file.entries
        return cache
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(CacheFile(version: Self.version, entries: entries))
        try data.write(to: url, options: .atomic)
    }

    /// The cached track, if the file hasn't changed since it was read.
    func track(for file: DiscoveredFile) -> Track? {
        guard let entry = entries[file.path], entry.size == file.size, entry.modified == file.modified else { return nil }
        return entry.track
    }

    mutating func insert(_ track: Track, for file: DiscoveredFile) {
        entries[file.path] = Entry(size: file.size, modified: file.modified, track: track)
    }

    /// Drops entries for files under `roots` that a complete scan didn't find,
    /// because they've been moved or deleted. Entries elsewhere are kept.
    /// Returns how many were dropped.
    @discardableResult
    mutating func removeMissing(under roots: [URL], found: Set<String>) -> Int {
        let rootPaths = roots.map(\.standardizedFileURL.filePath)
        let before = entries.count
        entries = entries.filter { path, _ in
            found.contains(path) || !rootPaths.contains { FolderEnumerator.isPath(path, inFolder: $0) }
        }
        return before - entries.count
    }
}

private struct CacheFile: Codable {
    var version: Int
    var entries: [String: ScanCache.Entry]
}
