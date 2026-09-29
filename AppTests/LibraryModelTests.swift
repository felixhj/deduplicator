import DedupCore
import DedupScanner
import Foundation
import Testing
@testable import Deduplicator

/// The whole flow: folders in, scan, duplicates out.
@MainActor
struct LibraryModelTests {
    let storage = TestDefaults()

    @Test func scanningAFolderFindsItsDuplicates() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "DeduplicatorAppTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for (name, title) in [("a.wav", "Strings of Life"), ("b.aiff", "Strings Of Life"), ("c.wav", "Something Else")] {
            let url = folder.appending(path: name)
            try AudioFiles.write(to: url, seconds: 1)
            try TagLibFile.write(["TITLE": [title], "ARTIST": ["Derrick May"]], to: url)
        }

        let library = LibraryModel(defaults: storage.defaults, cacheURL: folder.appending(path: "Cache/ScanCache.json"), waveformFolder: nil, removalLog: nil)
        library.addFolders([folder])
        library.scan()
        for _ in 0..<500 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .finished(let summary) = library.state else {
            Issue.record("The scan didn't finish: \(library.state)")
            return
        }
        #expect(summary.trackCount == 3)
        #expect(summary.formatCounts.map(\.format) == [.aiff, .wav])
        #expect(library.issues.isEmpty)

        try await waitForMatching(library.results)
        let groups = library.results.shownGroups
        #expect(groups.count == 1)
        let names = groups.first?.trackIDs.compactMap { library.results.tracks[$0]?.url.lastPathComponent }
        #expect(Set(names ?? []) == ["a.wav", "b.aiff"])
    }

    @Test func foldersAreKeptWithoutDuplicates() {
        let library = LibraryModel(defaults: storage.defaults, cacheURL: nil, waveformFolder: nil, removalLog: nil)
        let music = URL(filePath: "/Music", directoryHint: .isDirectory)
        library.addFolders([music, URL(filePath: "/Music/", directoryHint: .isDirectory), URL(filePath: "/Other", directoryHint: .isDirectory)])
        #expect(library.folders.count == 2)

        let reopened = LibraryModel(defaults: storage.defaults, cacheURL: nil, waveformFolder: nil, removalLog: nil)
        #expect(reopened.folders.map { $0.path(percentEncoded: false) } == ["/Music/", "/Other/"])
        reopened.removeFolders([reopened.folders[0]])
        #expect(LibraryModel(defaults: storage.defaults, cacheURL: nil, waveformFolder: nil, removalLog: nil).folders.count == 1)
    }

    @Test func scanningEmptiesThePlayer() {
        let library = LibraryModel(defaults: storage.defaults, cacheURL: nil, waveformFolder: nil, removalLog: nil)
        library.addFolders([URL(filePath: "/Nowhere", directoryHint: .isDirectory)])
        library.player.select(Fixtures.library[0], copies: Array(Fixtures.library.prefix(3)))
        library.scan()
        #expect(library.player.track == nil)
        library.cancelScan()
    }

    @Test func nothingIsChangingFilesAtFirst() {
        let library = LibraryModel(defaults: storage.defaults, cacheURL: nil, waveformFolder: nil, removalLog: nil)
        #expect(!library.isChangingFiles)
        #expect(!library.hasResults)
    }

    @Test func scanNeedsAFolder() {
        let library = LibraryModel(defaults: storage.defaults, cacheURL: nil, waveformFolder: nil, removalLog: nil)
        #expect(!library.canScan)
        library.scan()
        #expect(!library.isScanning)
    }
}
