import DedupCore
import DedupScanner
import Foundation
import Testing
@testable import Deduplicator

/// Copying tags between real files.
@MainActor
struct TagWriterTests {
    let storage = TestDefaults()
    let folder = TemporaryFolder()

    var logURL: URL { folder.url.appending(path: "Support/TagEditLog.json") }

    /// The keeper (0) and a copy with more tags (1), from `Fixtures.taggedPair`.
    func makeLibrary() async throws -> (LibraryModel, keeper: Track, copy: Track) {
        let tracks = try Fixtures.taggedPair(in: folder.url)
        let library = LibraryModel(defaults: storage.defaults, cacheURL: nil, waveformFolder: nil, removalLog: nil, tagLog: logURL)
        library.results.load(tracks)
        try await waitForMatching(library.results)
        #expect(library.results.shownGroups.map(\.trackIDs) == [[0, 1]])
        return (library, tracks[0], tracks[1])
    }

    @Test func tagsGoToTheCopyBeingKept() async throws {
        let (library, keeper, copy) = try await makeLibrary()
        let writer = library.tagWriter
        let copies = [keeper, copy]
        #expect(writer.defaultDestination(from: 1, among: copies) == 0)
        library.results.setMarked([0], true)
        #expect(writer.defaultDestination(from: 0, among: copies) == 1, "The only copy not marked")
        #expect(writer.defaultDestination(from: 1, among: copies) == 0, "Every other copy is marked, so the first")
    }

    @Test func writingCopiesTheChosenTagsAndShowsThem() async throws {
        let (library, keeper, copy) = try await makeLibrary()
        let writer = library.tagWriter
        let rows = TagCopy.compare(source: try #require(writer.tags(of: copy)), destination: try #require(writer.tags(of: keeper)))
        #expect(rows.filter(\.fillsGap).map(\.key) == ["DATE", "COMMENT", "BPM"])

        let changes = TagCopy.changes(copying: ["COMMENT", "BPM"], in: rows)
        let revision = library.results.revision
        let problem = try await writer.write(changes, before: ["COMMENT": [], "BPM": []], to: keeper, from: copy)
        #expect(problem == nil)

        let written = try TagLibFile.read(keeper.url).properties
        #expect(written["COMMENT"] == ["Ripped from vinyl"] && written["BPM"] == ["123"])
        #expect(written["TITLE"] == ["Strings of Life"], "Other tags are left alone")
        #expect(written["DATE"] == nil)

        let shown = try #require(library.results.tracks[0])
        #expect(shown.comment == "Ripped from vinyl" && shown.tags["BPM"] == "123")
        #expect(shown.fileSize != keeper.fileSize)
        #expect(library.results.revision > revision)

        let log = try TagEditLog.load(from: logURL)
        #expect(log.edits.map(\.file) == [keeper.url])
        #expect(log.edits.first?.after == changes)
        #expect(log.edits.first?.before == ["COMMENT": [], "BPM": []])
    }

    @Test func thePlayerLetsGoOfTheFileBeingWritten() async throws {
        let (library, keeper, copy) = try await makeLibrary()
        library.player.select(keeper, copies: [keeper, copy])
        _ = try await library.tagWriter.write(["COMMENT": ["New"]], before: ["COMMENT": []], to: keeper, from: copy)
        #expect(library.player.track == nil)
    }

    @Test func aFileThatCantBeWrittenSaysWhy() async throws {
        let (library, keeper, copy) = try await makeLibrary()
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: keeper.url.path(percentEncoded: false))
        await #expect(throws: TagLibError.self) {
            try await library.tagWriter.write(["COMMENT": ["New"]], before: ["COMMENT": []], to: keeper, from: copy)
        }
        #expect(TagWriter.describe(TagLibError.cannotOpen(path: "")) == "The file can't be opened for writing. It may be locked, read-only or moved.")
        #expect(!FileManager.default.fileExists(atPath: logURL.path(percentEncoded: false)), "Nothing was written, so nothing is logged")
    }
}
