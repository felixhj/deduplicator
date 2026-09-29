import DedupCore
import Foundation

public struct ScanProgress: Sendable, Hashable {
    public enum Phase: Sendable, Hashable {
        case finding, reading, saving
    }

    public var phase: Phase
    /// Audio files found so far.
    public var found: Int
    /// Files read, or taken from the cache.
    public var completed: Int

    public init(phase: Phase, found: Int, completed: Int) {
        self.phase = phase
        self.found = found
        self.completed = completed
    }

    /// Progress through reading, from 0 to 1.
    public var fractionCompleted: Double {
        found == 0 ? 0 : Double(completed) / Double(found)
    }
}

public struct ScanResult: Sendable {
    /// Sorted by path. Each track's `id` is its index here.
    public var tracks: [Track]
    public var issues: [ScanIssue]
    /// Tracks taken from the cache instead of being read.
    public var cachedCount: Int
}

/// Finds audio files under folders and reads them into tracks, several at a
/// time, reusing cached tracks for files that haven't changed.
public struct LibraryScanner: Sendable {
    public typealias ProgressHandler = @Sendable (ScanProgress) -> Void

    /// Enough parallel reads to keep a fast disk busy without flooding a slow one.
    public static let defaultConcurrency = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 8))

    public var reader: any TrackReader
    /// Where the scan cache lives. Nil turns caching off.
    public var cacheURL: URL?
    public var maxConcurrentReads: Int

    public init(
        reader: any TrackReader = AudioFileReader(),
        cacheURL: URL? = nil,
        maxConcurrentReads: Int = LibraryScanner.defaultConcurrency
    ) {
        self.reader = reader
        self.cacheURL = cacheURL
        self.maxConcurrentReads = max(1, maxConcurrentReads)
    }

    /// Scans `roots` recursively. Cancelling the task stops the scan and throws
    /// `CancellationError`, after saving what was read so far to the cache.
    public func scan(_ roots: [URL], progress: ProgressHandler? = nil) async throws -> ScanResult {
        async let loadedCache = loadCache()
        var throttle = ProgressThrottle(handler: progress)

        let (scanRoots, rootIssues) = FolderEnumerator.scanRoots(roots)
        let (files, folderIssues) = try FolderEnumerator.audioFiles(in: scanRoots) { found in
            throttle.report(ScanProgress(phase: .finding, found: found, completed: 0))
        }
        var cache = await loadedCache

        var cached: [Int: Track] = [:]
        var toRead: [Int] = []
        for (index, file) in files.enumerated() {
            if let track = cache.track(for: file) { cached[index] = track } else { toRead.append(index) }
        }
        throttle.report(ScanProgress(phase: .reading, found: files.count, completed: cached.count), force: true)

        let read = await readFiles(toRead.map { ($0, files[$0]) }) { completed in
            throttle.report(ScanProgress(phase: .reading, found: files.count, completed: cached.count + completed))
        }
        var inserted = 0
        for (index, result) in read where result.problems.isEmpty {
            cache.insert(result.track, for: files[index])
            inserted += 1
        }

        if Task.isCancelled {
            if inserted > 0 { _ = saveCache(cache) }
            throw CancellationError()
        }

        throttle.report(ScanProgress(phase: .saving, found: files.count, completed: files.count), force: true)
        let removed = cache.removeMissing(under: scanRoots.map(\.url), found: Set(files.map(\.path)))
        // Files with problems aren't cached, so they're read again next time.
        let cacheIssue = inserted + removed > 0 ? saveCache(cache) : nil

        var result = Self.result(files: files, cached: cached, read: read)
        result.issues = rootIssues + folderIssues + result.issues + [cacheIssue].compactMap { $0 }
        return result
    }

    /// Puts cached and freshly read tracks in path order, numbering them, with
    /// each file's reading problems as issues.
    private static func result(files: [DiscoveredFile], cached: [Int: Track], read: [Int: TrackReadResult]) -> ScanResult {
        var tracks: [Track] = []
        var issues: [ScanIssue] = []
        tracks.reserveCapacity(files.count)
        for (index, file) in files.enumerated() {
            var track = cached[index] ?? read[index]?.track ?? TrackBuilder.track(for: file, metadata: nil, decoded: nil)
            track.id = index
            track.scanRoot = file.root
            tracks.append(track)
            issues += (read[index]?.problems ?? []).map { ScanIssue(url: file.url, message: $0) }
        }
        return ScanResult(tracks: tracks, issues: issues, cachedCount: cached.count)
    }

    /// Reads files in a task group with at most `maxConcurrentReads` at once.
    /// Stops starting new reads once the task is cancelled.
    private func readFiles(
        _ files: [(index: Int, file: DiscoveredFile)],
        completed: (Int) -> Void
    ) async -> [Int: TrackReadResult] {
        let reader = self.reader
        return await withTaskGroup(of: (Int, TrackReadResult?).self) { group in
            var pending = files.makeIterator()
            var results: [Int: TrackReadResult] = [:]
            for _ in 0..<maxConcurrentReads {
                guard let (index, file) = pending.next() else { break }
                group.addTask { (index, Task.isCancelled ? nil : reader.read(file)) }
            }
            for await (index, result) in group {
                if let result { results[index] = result }
                completed(results.count)
                if !Task.isCancelled, let (index, file) = pending.next() {
                    group.addTask { (index, Task.isCancelled ? nil : reader.read(file)) }
                }
            }
            return results
        }
    }

    private func loadCache() -> ScanCache {
        cacheURL.map(ScanCache.load(from:)) ?? ScanCache()
    }

    /// Saves the cache, returning an issue instead of throwing: a scan is still
    /// useful when its cache can't be written.
    private func saveCache(_ cache: ScanCache) -> ScanIssue? {
        guard let cacheURL else { return nil }
        do {
            try cache.save(to: cacheURL)
            return nil
        } catch {
            return ScanIssue(url: cacheURL, message: "Couldn't save the scan cache: \(error.localizedDescription)")
        }
    }
}

/// Passes progress on at most ten times a second, so a big scan doesn't flood the UI.
struct ProgressThrottle {
    let handler: LibraryScanner.ProgressHandler?
    private var lastReport: ContinuousClock.Instant?

    init(handler: LibraryScanner.ProgressHandler?) {
        self.handler = handler
    }

    mutating func report(_ progress: ScanProgress, force: Bool = false) {
        guard let handler else { return }
        let now = ContinuousClock.now
        if !force, let lastReport, now - lastReport < .milliseconds(100) { return }
        lastReport = now
        handler(progress)
    }
}
