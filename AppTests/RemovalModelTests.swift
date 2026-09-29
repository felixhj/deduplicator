import DedupCore
import Foundation
import Testing
@testable import Deduplicator

/// Removing and undoing with real files, in a folder of the test's own.
@MainActor
struct RemovalModelTests {
    let storage = TestDefaults()
    let folder = TemporaryFolder()

    var bin: URL { folder.url.appending(path: "Bin", directoryHint: .isDirectory) }
    var logURL: URL { folder.url.appending(path: "Support/RemovalLog.json") }

    /// The fixture library as files in a scanned folder called Music. Its
    /// groups are [0, 1, 2] and [3, 4].
    func makeLibrary(mover: TestMover? = nil) async throws -> (LibraryModel, [Track]) {
        let music = folder.url.appending(path: "Music", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        let tracks = try Fixtures.playableLibrary(in: music, seconds: 0.2)
        let library = reopen(mover: mover)
        library.addFolders([music])
        library.results.load(tracks)
        try await waitForMatching(library.results)
        return (library, tracks)
    }

    func reopen(mover: TestMover? = nil) -> LibraryModel {
        LibraryModel(defaults: storage.defaults, cacheURL: nil, waveformFolder: nil, removalLog: logURL, fileMover: mover ?? TestMover(bin: bin))
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test func removingMovesMarkedCopiesToTheBinAndOutOfTheResults() async throws {
        let (library, tracks) = try await makeLibrary()
        let results = library.results
        results.setMarked([1, 4], true)
        #expect(library.canRemove)
        let report = await library.removal.removeMarked(to: .moveToBin)
        #expect(report == RemovalModel.Report(summary: "Moved 2 files to the Bin.", failures: []))
        #expect(!exists(tracks[1].url) && !exists(tracks[4].url))
        #expect(exists(bin.appending(path: tracks[1].url.lastPathComponent)))
        #expect(results.shownGroups.map(\.trackIDs) == [[0, 2]], "A group left with one copy goes")
        #expect(results.marked.isEmpty)
        #expect(library.removal.lastRemoval == "Moved 2 files to the Bin.")
        #expect(library.removal.canUndo)
        #expect(try RemovalLog.load(from: logURL).operations.map { $0.records.map(\.trackID) } == [[1, 4]])
    }

    @Test func removingToAFolderMirrorsTheScannedFolder() async throws {
        let (library, tracks) = try await makeLibrary()
        library.results.setMarked([2], true)
        let dupes = folder.url.appending(path: "Dupes", directoryHint: .isDirectory)
        let report = await library.removal.removeMarked(to: .moveToFolder(dupes))
        #expect(report?.summary == "Moved 1 file to “Dupes”.")
        #expect(exists(dupes.appending(path: "Music/\(tracks[2].url.lastPathComponent)")))
    }

    @Test func undoingPutsFilesAndCopiesBack() async throws {
        let (library, tracks) = try await makeLibrary()
        library.results.setMarked([1, 4], true)
        _ = await library.removal.removeMarked(to: .moveToBin)
        let report = await library.removal.undoLast()
        #expect(report == RemovalModel.Report(summary: "Put back 2 files.", failures: []))
        #expect(exists(tracks[1].url) && exists(tracks[4].url))
        try await waitForMatching(library.results)
        #expect(library.results.shownGroups.map(\.trackIDs) == [[0, 1, 2], [3, 4]])
        #expect(!library.removal.canUndo)
        #expect(library.removal.lastRemoval == nil)
        #expect(try RemovalLog.load(from: logURL).operations.first?.undoneAt != nil)
    }

    @Test func undoingAfterANewScanAsksForAnother() async throws {
        let (library, tracks) = try await makeLibrary()
        library.results.setMarked([1], true)
        _ = await library.removal.removeMarked(to: .moveToBin)
        library.results.load(tracks.filter { $0.id != 1 })
        let report = await library.removal.undoLast()
        #expect(report?.summary == "Put back 1 file. Scan again to see it in the results.")
        #expect(exists(tracks[1].url))
        #expect(library.results.tracks[1] == nil)
    }

    @Test func theLastRemovalCanBeUndoneAfterReopening() async throws {
        let (library, tracks) = try await makeLibrary()
        library.results.setMarked([1, 2], true)
        _ = await library.removal.removeMarked(to: .moveToBin)

        let reopened = reopen()
        #expect(reopened.removal.undoable?.records.map(\.trackID) == [1, 2])
        let report = await reopened.removal.undoLast()
        #expect(report?.summary == "Put back 2 files. Scan again to see them in the results.")
        #expect(exists(tracks[1].url) && exists(tracks[2].url))
    }

    @Test func filesThatCantBeMovedAreReportedAndStayMarked() async throws {
        let (library, tracks) = try await makeLibrary()
        library.results.setMarked([1, 4], true)
        try FileManager.default.removeItem(at: tracks[4].url)
        let report = try #require(await library.removal.removeMarked(to: .moveToBin))
        #expect(report.summary == "Moved 1 file to the Bin. 1 file couldn't be moved.")
        #expect(report.failures.map(\.trackID) == [4])
        #expect(!report.isComplete)
        #expect(library.results.tracks[4] != nil)
        #expect(library.results.marked == [4])
    }

    @Test func thePlayerLetsGoOfARemovedCopy() async throws {
        let (library, tracks) = try await makeLibrary()
        library.player.select(tracks[1], copies: Array(tracks[0...2]))
        library.results.setMarked([2], true)
        _ = await library.removal.removeMarked(to: .moveToBin)
        #expect(library.player.track?.id == 1, "Removing another copy leaves it in the player")
        library.results.setMarked([1], true)
        _ = await library.removal.removeMarked(to: .moveToBin)
        #expect(library.player.track == nil)
    }

    @Test func stoppingKeepsWhatWasMoved() async throws {
        let (library, _) = try await makeLibrary(mover: TestMover(bin: bin, delay: 0.3))
        library.results.setMarked([1, 2, 4], true)
        async let report = library.removal.removeMarked(to: .moveToBin)
        try await waitUntil("the removal to start") { library.removal.isBusy }
        #expect(!library.canRemove && !library.canScan && !library.canAutoSelect)
        library.removal.stop()
        let finished = await report
        #expect(finished?.summary == "Stopped after moving 1 of 3 files to the Bin.")
        #expect(finished?.isComplete == false)
        #expect(library.removal.undoable?.records.count == 1)
        #expect(library.results.marked == [2, 4])
    }

    @Test func anUnreadableLogIsPutAsideAndReportedOnce() async throws {
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a log".utf8).write(to: logURL)
        let (library, _) = try await makeLibrary()
        #expect(library.removal.log.operations.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: logURL.deletingLastPathComponent().path(percentEncoded: false))
        #expect(files.contains { $0.hasPrefix("RemovalLog (unreadable") })

        library.results.setMarked([1], true)
        let report = await library.removal.removeMarked(to: .moveToBin)
        #expect(report?.summary.hasSuffix("so it was put aside as “\(files.first { $0.hasPrefix("RemovalLog (unreadable") } ?? "")”.") == true)
        #expect(report?.isComplete == false)
        #expect(library.removal.logProblem == nil)
    }

    @Test func commandsWaitWhileASheetIsUp() async throws {
        let (library, _) = try await makeLibrary()
        library.results.setMarked([1], true)
        #expect(library.canRemove && library.canAutoSelect && library.canScan)
        library.results.isAutoSelecting = true
        #expect(!library.canRemove && !library.canAutoSelect && !library.canScan)
    }

    @Test func summariesSayWhatHappened() {
        let record = RemovalRecord(trackID: 1, original: URL(filePath: "/a"), destination: URL(filePath: "/b"))
        let failure = RemovalFailure(trackID: 2, source: URL(filePath: "/c"), message: "No")
        func summary(_ records: [RemovalRecord], _ failures: [RemovalFailure], planned: Int) -> String {
            RemovalModel.summary(of: RemovalOperation(mode: .moveToBin, records: records, failures: failures), planned: planned)
        }
        #expect(summary([record], [], planned: 1) == "Moved 1 file to the Bin.")
        #expect(summary([], [failure], planned: 1) == "The file couldn't be moved.")
        #expect(summary([], [failure, failure], planned: 2) == "None of the 2 files could be moved.")
        #expect(summary([record], [failure], planned: 3) == "Stopped after moving 1 of 3 files to the Bin. 1 file couldn't be moved.")
        #expect(RemovalModel.summary(restored: 0, failed: 2) == "None of the 2 files could be put back.")
        #expect(RemovalModel.summary(restored: 3, failed: 1) == "Put back 3 files. 1 file couldn't be put back.")
    }
}
