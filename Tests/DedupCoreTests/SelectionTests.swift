import Foundation
import Testing
@testable import DedupCore

@Suite struct KeeperSelectorTests {
    private func track(_ id: Int, _ format: AudioFormat, bitrate: Int? = nil, duration: Double? = 300, path: String? = nil) -> Track {
        Track(
            id: id,
            url: URL(fileURLWithPath: path ?? "/music/\(id).\(format.rawValue)"),
            title: "Song",
            artist: "A",
            duration: duration,
            audio: AudioProperties(format: format, bitrate: bitrate)
        )
    }

    @Test func prefersLosslessThenBitrate() {
        let mp3Low = track(1, .mp3, bitrate: 128)
        let mp3High = track(2, .mp3, bitrate: 320)
        let flac = track(3, .flac, bitrate: 900)
        let selector = KeeperSelector()
        #expect(selector.keeper(among: [mp3Low, mp3High, flac])?.id == 3)
        #expect(selector.keeper(among: [mp3Low, mp3High])?.id == 2)
    }

    @Test func tieKeepsFirst() {
        let a = track(1, .mp3, bitrate: 320)
        let b = track(2, .mp3, bitrate: 320)
        #expect(KeeperSelector().keeper(among: [a, b])?.id == 1)
        #expect(KeeperSelector().keeper(among: [b, a])?.id == 2)
    }

    @Test func missingValueRanksLowest() {
        let unknown = track(1, .mp3, bitrate: nil)
        let known = track(2, .mp3, bitrate: 128)
        #expect(KeeperSelector(rules: [.higherBitrate]).keeper(among: [unknown, known])?.id == 2)
    }

    @Test func durationToleranceIgnoresRounding() {
        let a = track(1, .mp3, bitrate: 320, duration: 300.2)
        let b = track(2, .mp3, bitrate: 320, duration: 300.0)
        #expect(KeeperSelector(rules: [.longerDuration]).keeper(among: [b, a])?.id == 2)
    }

    @Test func pathRules() {
        let inbox = track(1, .mp3, path: "/music/Inbox/song.mp3")
        let library = track(2, .mp3, path: "/music/Library/song.mp3")
        #expect(KeeperSelector(rules: [.pathContains("library")]).keeper(among: [inbox, library])?.id == 2)
        #expect(KeeperSelector(rules: [.pathDoesNotContain("inbox")]).keeper(among: [inbox, library])?.id == 2)
    }

    @Test func preferFormat() {
        let mp3 = track(1, .mp3)
        let aiff = track(2, .aiff)
        let wav = track(3, .wav)
        #expect(KeeperSelector(rules: [.preferFormat(.aiff)]).keeper(among: [mp3, wav, aiff])?.id == 2)
    }

    @Test func autoSelectMarksAllButKeeper() {
        let tracks = [track(1, .mp3, bitrate: 128), track(2, .flac), track(3, .mp3, bitrate: 320),
                      track(4, .mp3, bitrate: 192), track(5, .mp3, bitrate: 256)]
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let groups = [
            DuplicateGroup(id: 0, trackIDs: [1, 2, 3], confidence: 1, reasons: []),
            DuplicateGroup(id: 1, trackIDs: [4, 5], confidence: 1, reasons: []),
        ]
        #expect(KeeperSelector().autoSelect(groups: groups, tracks: byID) == [1, 3, 4])
    }

    @Test func choicesNameEachGroupsKeeper() {
        let tracks = [track(1, .mp3, bitrate: 128), track(2, .flac), track(3, .mp3, bitrate: 320)]
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let groups = [DuplicateGroup(id: 7, trackIDs: [1, 2, 3], confidence: 1, reasons: [])]
        #expect(KeeperSelector().choices(for: groups, tracks: byID) == [KeeperChoice(groupID: 7, keeper: 2, others: [1, 3])])
        #expect(KeeperSelector().choices(for: groups, tracks: [:]).isEmpty, "A group whose tracks are gone has no keeper")
    }

    @Test func rulesRoundTripThroughJSON() throws {
        let selector = KeeperSelector(rules: [.pathContains("x"), .preferFormat(.flac), .newerFile])
        let data = try JSONEncoder().encode(selector)
        #expect(try JSONDecoder().decode(KeeperSelector.self, from: data) == selector)
    }
}

@Suite struct RemovalPlannerTests {
    private func track(_ id: Int, _ path: String, root: String?) -> Track {
        Track(id: id, url: URL(fileURLWithPath: path), scanRoot: root.map { URL(fileURLWithPath: $0) })
    }

    @Test func binPlanHasNoDestinations() {
        let plan = RemovalPlanner.plan([track(1, "/m/a.mp3", root: "/m")], mode: .moveToBin)
        #expect(plan == [PlannedMove(trackID: 1, source: URL(fileURLWithPath: "/m/a.mp3"), destination: nil)])
    }

    @Test func mirrorsFolderStructure() {
        let t = track(1, "/Users/me/Music/House/2020/song.mp3", root: "/Users/me/Music")
        let plan = RemovalPlanner.plan([t], mode: .moveToFolder(URL(fileURLWithPath: "/Dupes")))
        #expect(plan[0].destination?.path == "/Dupes/Music/House/2020/song.mp3")
    }

    @Test func rootsWithSameNameDoNotCollide() {
        let a = track(1, "/Volumes/A/Music/x.mp3", root: "/Volumes/A/Music")
        let b = track(2, "/Volumes/B/Music/x.mp3", root: "/Volumes/B/Music")
        let plan = RemovalPlanner.plan([a, b], mode: .moveToFolder(URL(fileURLWithPath: "/Dupes")))
        #expect(plan.map { $0.destination?.path } == ["/Dupes/Music/x.mp3", "/Dupes/Music 2/x.mp3"])
    }

    @Test func noScanRootUsesParentFolder() {
        let t = track(1, "/somewhere/Album/x.mp3", root: nil)
        let plan = RemovalPlanner.plan([t], mode: .moveToFolder(URL(fileURLWithPath: "/Dupes")))
        #expect(plan[0].destination?.path == "/Dupes/Album/x.mp3")
    }

    @Test func movesIntoScannedFoldersAreFound() {
        let t = track(1, "/Users/me/Music/House/x.mp3", root: "/Users/me/Music")
        let scanned = [URL(fileURLWithPath: "/Users/me/Music")]
        func check(_ folder: String) -> PlannedMove? {
            RemovalPlanner.moveIntoFolders(scanned, in: RemovalPlanner.plan([t], mode: .moveToFolder(URL(fileURLWithPath: folder))))
        }
        #expect(check("/Users/me/Music/Dupes") != nil, "Inside the scanned folder")
        #expect(check("/Users/me")?.destination?.path == "/Users/me/Music/House/x.mp3", "Onto the file itself")
        #expect(check("/Users/me/Dupes") == nil)
        #expect(check("/Users/me/Musical") == nil, "A name that merely starts the same")
        #expect(RemovalPlanner.moveIntoFolders(scanned, in: RemovalPlanner.plan([t], mode: .moveToBin)) == nil)
    }

    @Test func uniqueDestination() {
        let taken: Set<String> = ["/d/x.mp3", "/d/x 2.mp3"]
        let url = RemovalPlanner.uniqueDestination(for: URL(fileURLWithPath: "/d/x.mp3")) { taken.contains($0.path) }
        #expect(url.path == "/d/x 3.mp3")
        let free = RemovalPlanner.uniqueDestination(for: URL(fileURLWithPath: "/d/y.mp3")) { taken.contains($0.path) }
        #expect(free.path == "/d/y.mp3")
    }
}

/// In-memory file system for testing moves.
final class FakeFileMover: FileMover, @unchecked Sendable {
    private let lock = NSLock()
    private var files: Set<String>
    var failOn: Set<String> = []

    init(files: [String]) {
        self.files = Set(files)
    }

    var paths: Set<String> { lock.withLock { files } }

    func fileExists(at url: URL) -> Bool { lock.withLock { files.contains(url.path) } }

    func createDirectory(at url: URL) throws {}

    func moveItem(at source: URL, to destination: URL) throws {
        try lock.withLock {
            guard !failOn.contains(source.path), files.contains(source.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            guard !files.contains(destination.path) else { throw CocoaError(.fileWriteFileExists) }
            files.remove(source.path)
            files.insert(destination.path)
        }
    }

    func trashItem(at url: URL) throws -> URL {
        let trashed = URL(fileURLWithPath: "/Trash").appendingPathComponent(url.lastPathComponent)
        try moveItem(at: url, to: trashed)
        return trashed
    }
}

@Suite struct RemovalExecutorTests {
    private func track(_ id: Int, _ path: String) -> Track {
        Track(id: id, url: URL(fileURLWithPath: path), scanRoot: URL(fileURLWithPath: "/m"))
    }

    @Test func movesToFolderAndUndoes() {
        let fs = FakeFileMover(files: ["/m/a/x.mp3", "/m/b/y.mp3"])
        let executor = RemovalExecutor(mover: fs)
        let mode = RemovalMode.moveToFolder(URL(fileURLWithPath: "/Dupes"))
        let plan = RemovalPlanner.plan([track(1, "/m/a/x.mp3"), track(2, "/m/b/y.mp3")], mode: mode)

        let op = executor.execute(plan, mode: mode)
        #expect(op.failures.isEmpty)
        #expect(fs.paths == ["/Dupes/m/a/x.mp3", "/Dupes/m/b/y.mp3"])

        let undo = executor.undo(op)
        #expect(undo.failures.isEmpty)
        #expect(fs.paths == ["/m/a/x.mp3", "/m/b/y.mp3"])
    }

    @Test func trashAndUndo() {
        let fs = FakeFileMover(files: ["/m/x.mp3"])
        let executor = RemovalExecutor(mover: fs)
        let op = executor.execute(RemovalPlanner.plan([track(1, "/m/x.mp3")], mode: .moveToBin), mode: .moveToBin)
        #expect(op.records.map(\.destination.path) == ["/Trash/x.mp3"])
        #expect(fs.paths == ["/Trash/x.mp3"])
        _ = executor.undo(op)
        #expect(fs.paths == ["/m/x.mp3"])
    }

    @Test func existingFileAtDestinationGetsNewName() {
        let fs = FakeFileMover(files: ["/m/x.mp3", "/Dupes/m/x.mp3"])
        let mode = RemovalMode.moveToFolder(URL(fileURLWithPath: "/Dupes"))
        let op = RemovalExecutor(mover: fs).execute(RemovalPlanner.plan([track(1, "/m/x.mp3")], mode: mode), mode: mode)
        #expect(op.records.map(\.destination.path) == ["/Dupes/m/x 2.mp3"])
    }

    @Test func failuresAreRecordedAndOthersContinue() {
        let fs = FakeFileMover(files: ["/m/x.mp3", "/m/y.mp3"])
        fs.failOn = ["/m/x.mp3"]
        let op = RemovalExecutor(mover: fs).execute(
            RemovalPlanner.plan([track(1, "/m/x.mp3"), track(2, "/m/y.mp3")], mode: .moveToBin),
            mode: .moveToBin
        )
        #expect(op.failures.map(\.trackID) == [1])
        #expect(op.records.map(\.trackID) == [2])
    }

    @Test func undoWillNotOverwrite() {
        let fs = FakeFileMover(files: ["/m/x.mp3"])
        let executor = RemovalExecutor(mover: fs)
        let op = executor.execute(RemovalPlanner.plan([track(1, "/m/x.mp3")], mode: .moveToBin), mode: .moveToBin)
        // A new file has since appeared at the original path.
        let occupied = FakeFileMover(files: ["/Trash/x.mp3", "/m/x.mp3"])
        let result = RemovalExecutor(mover: occupied).undo(op)
        #expect(result.restored.isEmpty)
        #expect(result.failures.count == 1)
    }

    @Test func reportsProgress() {
        let fs = FakeFileMover(files: ["/m/x.mp3", "/m/y.mp3"])
        let executor = RemovalExecutor(mover: fs)
        var done: [Int] = []
        let op = executor.execute(RemovalPlanner.plan([track(1, "/m/x.mp3"), track(2, "/m/y.mp3")], mode: .moveToBin), mode: .moveToBin) {
            done.append($0)
        }
        #expect(done == [1, 2])
        done = []
        _ = executor.undo(op) { done.append($0) }
        #expect(done == [1, 2])
    }

    @Test func stopsWhenCancelled() async {
        let fs = FakeFileMover(files: ["/m/x.mp3", "/m/y.mp3", "/m/z.mp3"])
        let plan = RemovalPlanner.plan([track(1, "/m/x.mp3"), track(2, "/m/y.mp3"), track(3, "/m/z.mp3")], mode: .moveToBin)
        let op = await Task {
            RemovalExecutor(mover: fs).execute(plan, mode: .moveToBin) { done in
                if done == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }.value
        #expect(op.records.map(\.trackID) == [1])
        #expect(op.failures.isEmpty)
        #expect(fs.paths == ["/Trash/x.mp3", "/m/y.mp3", "/m/z.mp3"])
    }

    @Test func undoFailuresSayWhy() {
        let fs = FakeFileMover(files: ["/m/x.mp3"])
        let executor = RemovalExecutor(mover: fs)
        let op = executor.execute(RemovalPlanner.plan([track(1, "/m/x.mp3")], mode: .moveToBin), mode: .moveToBin)
        let emptied = RemovalExecutor(mover: FakeFileMover(files: [])).undo(op)
        #expect(emptied.failures.map(\.message) == ["The file is no longer at /Trash/x.mp3."])
        let occupied = RemovalExecutor(mover: FakeFileMover(files: ["/Trash/x.mp3", "/m/x.mp3"])).undo(op)
        #expect(occupied.failures.map(\.message) == ["Another file is already at /m/x.mp3."])
    }

    @Test func logKeepsUndoFailuresAndReadsOlderEntries() throws {
        var log = RemovalLog()
        let op = RemovalOperation(mode: .moveToBin, records: [
            RemovalRecord(trackID: 1, original: URL(fileURLWithPath: "/a"), destination: URL(fileURLWithPath: "/b")),
        ])
        log.append(op)
        let failure = RemovalFailure(trackID: 1, source: URL(fileURLWithPath: "/b"), message: "Gone")
        log.markUndone(op.id, failures: [failure])
        #expect(log.operations[0].undoFailures == [failure])

        // An entry written before undo failures were logged.
        let older = #"{"operations": [{"id": "\#(UUID().uuidString)", "date": "2026-09-29T12:00:00Z", "mode": {"moveToBin": {}}, "records": [], "failures": []}]}"#
        let decoded = try LogFile.decoder.decode(RemovalLog.self, from: Data(older.utf8))
        #expect(decoded.operations.first?.undoFailures == [])
    }

    @Test func logTracksLastUndoable() throws {
        var log = RemovalLog()
        let first = RemovalOperation(mode: .moveToBin, records: [
            RemovalRecord(trackID: 1, original: URL(fileURLWithPath: "/a"), destination: URL(fileURLWithPath: "/b")),
        ])
        let empty = RemovalOperation(mode: .moveToBin)
        log.append(first)
        log.append(empty)
        #expect(log.lastUndoable?.id == first.id)
        log.markUndone(first.id)
        #expect(log.lastUndoable == nil)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("log.json")
        try log.save(to: url)
        let loaded = try RemovalLog.load(from: url)
        #expect(loaded.operations.map(\.id) == log.operations.map(\.id))
        #expect(loaded.operations[0].undoneAt != nil)
    }
}
