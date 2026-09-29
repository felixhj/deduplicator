import DedupCore
import Foundation
import Testing
@testable import DedupScanner

struct LibraryScannerTests {
    /// Creates `names` (relative paths) under `folder/Music`, returning that root.
    func library(in folder: URL, _ names: [String]) throws -> URL {
        let root = folder.appending(path: "Music", directoryHint: .isDirectory)
        for name in names { try root.appending(path: name).create(name) }
        return root
    }

    @Test func tracksAreSortedAndNumbered() async throws {
        try await withTemporaryFolder { folder in
            let root = try library(in: folder, ["b.mp3", "A/c.flac", "a.m4a"])
            let result = try await LibraryScanner(reader: FakeReader()).scan([root])

            #expect(result.tracks.map(\.title) == ["c", "a", "b"])
            #expect(result.tracks.map(\.id) == [0, 1, 2])
            #expect(result.tracks.allSatisfy { $0.scanRoot == root.standardizedFileURL })
            #expect(result.issues.isEmpty)
            #expect(result.cachedCount == 0)
        }
    }

    @Test func rescanUsesCacheForUnchangedFiles() async throws {
        try await withTemporaryFolder { folder in
            let root = try library(in: folder, ["a.mp3", "b.mp3", "c.mp3"])
            let cacheURL = folder.appending(path: "Cache/ScanCache.json")

            let first = FakeReader()
            _ = try await LibraryScanner(reader: first, cacheURL: cacheURL).scan([root])
            #expect(first.totalReads == 3)

            try root.appending(path: "b.mp3").create("changed contents")
            let second = FakeReader()
            let result = try await LibraryScanner(reader: second, cacheURL: cacheURL).scan([root])
            #expect(second.readCounts == ["b.mp3": 1])
            #expect(result.cachedCount == 2)
            #expect(result.tracks.map(\.id) == [0, 1, 2])
            #expect(result.tracks.map(\.title) == ["a", "b", "c"])
        }
    }

    @Test func deletedFilesLeaveTheCache() async throws {
        try await withTemporaryFolder { folder in
            let root = try library(in: folder, ["a.mp3", "b.mp3"])
            let cacheURL = folder.appending(path: "ScanCache.json")
            _ = try await LibraryScanner(reader: FakeReader(), cacheURL: cacheURL).scan([root])
            #expect(ScanCache.load(from: cacheURL).count == 2)

            try FileManager.default.removeItem(at: root.appending(path: "b.mp3"))
            _ = try await LibraryScanner(reader: FakeReader(), cacheURL: cacheURL).scan([root])
            #expect(ScanCache.load(from: cacheURL).count == 1)
        }
    }

    @Test func cacheKeepsOtherFolders() async throws {
        try await withTemporaryFolder { folder in
            let music = try library(in: folder, ["a.mp3"])
            let other = folder.appending(path: "Other")
            try other.appending(path: "x.mp3").create()
            let cacheURL = folder.appending(path: "ScanCache.json")

            _ = try await LibraryScanner(reader: FakeReader(), cacheURL: cacheURL).scan([music, other])
            _ = try await LibraryScanner(reader: FakeReader(), cacheURL: cacheURL).scan([music])
            #expect(ScanCache.load(from: cacheURL).count == 2)
        }
    }

    @Test func problemsBecomeIssuesAndAreReadAgain() async throws {
        try await withTemporaryFolder { folder in
            let root = try library(in: folder, ["good.mp3", "bad.mp3"])
            let cacheURL = folder.appending(path: "ScanCache.json")
            let reader = FakeReader(problemFiles: ["bad.mp3"])

            let result = try await LibraryScanner(reader: reader, cacheURL: cacheURL).scan([root])
            #expect(result.tracks.count == 2)
            #expect(result.issues.map(\.url.lastPathComponent) == ["bad.mp3"])

            let again = FakeReader(problemFiles: ["bad.mp3"])
            _ = try await LibraryScanner(reader: again, cacheURL: cacheURL).scan([root])
            #expect(again.readCounts == ["bad.mp3": 1])
        }
    }

    @Test func missingFolderIsAnIssue() async throws {
        try await withTemporaryFolder { folder in
            let root = try library(in: folder, ["a.mp3"])
            let missing = folder.appending(path: "Unplugged Drive")
            let result = try await LibraryScanner(reader: FakeReader()).scan([root, missing])
            #expect(result.tracks.count == 1)
            #expect(result.issues.map(\.url.lastPathComponent) == ["Unplugged Drive"])
        }
    }

    @Test func unwritableCacheIsAnIssueNotAFailure() async throws {
        try await withTemporaryFolder { folder in
            let root = try library(in: folder, ["a.mp3"])
            let blocker = try folder.appending(path: "NotAFolder").create()
            let result = try await LibraryScanner(reader: FakeReader(), cacheURL: blocker.appending(path: "ScanCache.json")).scan([root])
            #expect(result.tracks.count == 1)
            #expect(result.issues.count == 1)
            #expect(result.issues.first?.message.hasPrefix("Couldn't save the scan cache") == true)
        }
    }

    @Test func readsAreBoundedAndParallel() async throws {
        try await withTemporaryFolder { folder in
            let root = try library(in: folder, (0..<24).map { "\($0).mp3" })
            let reader = FakeReader(delay: 0.02)
            _ = try await LibraryScanner(reader: reader, maxConcurrentReads: 3).scan([root])
            #expect(reader.totalReads == 24)
            #expect(reader.peakConcurrency <= 3)
            #expect(reader.peakConcurrency >= 2)
        }
    }

    @Test func progressEndsComplete() async throws {
        try await withTemporaryFolder { folder in
            let root = try library(in: folder, (0..<50).map { "\($0).mp3" })
            let log = ProgressLog()
            _ = try await LibraryScanner(reader: FakeReader()).scan([root]) { log.record($0) }

            let reports = log.all
            #expect(reports.last == ScanProgress(phase: .saving, found: 50, completed: 50))
            let reading = reports.filter { $0.phase == .reading }
            #expect(reading.first == ScanProgress(phase: .reading, found: 50, completed: 0))
            #expect(reading.map(\.completed) == reading.map(\.completed).sorted())
        }
    }

    @Test func cancellingKeepsWhatWasRead() async throws {
        try await withTemporaryFolder { folder in
            let root = try library(in: folder, (0..<40).map { String(format: "%02d.mp3", $0) })
            let cacheURL = folder.appending(path: "ScanCache.json")
            let reader = FakeReader(delay: 0.05)
            let scanner = LibraryScanner(reader: reader, cacheURL: cacheURL, maxConcurrentReads: 2)
            let log = ProgressLog()

            let task = Task { try await scanner.scan([root]) { log.record($0) } }
            // Waits for a few reads, giving up after five seconds rather than hanging.
            for _ in 0..<500 {
                if let last = log.all.last, last.phase == .reading, last.completed >= 4 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }

            let partial = ScanCache.load(from: cacheURL).count
            #expect(partial >= 4)
            #expect(partial < 40)

            let resumed = FakeReader()
            let result = try await LibraryScanner(reader: resumed, cacheURL: cacheURL).scan([root])
            #expect(result.tracks.count == 40)
            #expect(resumed.totalReads == 40 - partial)
            #expect(result.cachedCount == partial)
        }
    }
}

extension LibraryScannerTests {
    @Test func unchangedRescanDoesNotRewriteTheCache() async throws {
        try await withTemporaryFolder { folder in
            let root = try library(in: folder, ["a.mp3", "b.mp3"])
            let cacheURL = folder.appending(path: "ScanCache.json")
            _ = try await LibraryScanner(reader: FakeReader(), cacheURL: cacheURL).scan([root])
            let written = Date(timeIntervalSince1970: 1_000_000)
            try cacheURL.setModified(written)

            _ = try await LibraryScanner(reader: FakeReader(), cacheURL: cacheURL).scan([root])
            let modified = try cacheURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            #expect(modified == written)
        }
    }
}
