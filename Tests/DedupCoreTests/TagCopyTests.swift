import Foundation
import Testing
@testable import DedupCore

struct TagCopyTests {
    let source: [String: [String]] = [
        "TITLE": ["Strings of Life"], "ARTIST": ["Derrick May"], "COMMENT": ["Ripped from vinyl"],
        "DATE": ["1987"], "ENCODEDBY": ["LAME"], "BPM": ["123"], "ZZTOP": ["x"], "GENRE": [""],
    ]
    let destination: [String: [String]] = [
        "TITLE": ["Strings Of Life"], "ARTIST": ["Derrick May"], "DATE": ["1987-05"], "ENCODER": ["FLAC 1.4"],
    ]

    @Test func listsEveryTagDescriptiveOnesFirst() {
        let keys = TagCopy.compare(source: source, destination: destination).map(\.key)
        #expect(keys == ["TITLE", "ARTIST", "DATE", "GENRE", "COMMENT", "BPM", "ENCODEDBY", "ENCODER", "ZZTOP"])
    }

    @Test func onlyValuesThatWouldChangeSomethingCanBeCopied() {
        let rows = Dictionary(uniqueKeysWithValues: TagCopy.compare(source: source, destination: destination).map { ($0.key, $0) })
        #expect(rows["TITLE"]?.canCopy == true)
        #expect(rows["ARTIST"]?.canCopy == false, "The same already")
        #expect(rows["ENCODER"]?.canCopy == false, "Nothing to copy")
        #expect(rows["GENRE"]?.canCopy == false, "An empty value isn't copied")
    }

    @Test func gapsInDescriptiveTagsAreFilledByDefault() {
        let filled = TagCopy.compare(source: source, destination: destination).filter(\.fillsGap).map(\.key)
        #expect(filled == ["COMMENT", "BPM"], "Not TITLE or DATE, which the destination has, nor ENCODEDBY, which is technical")
    }

    @Test func changesCopyTheChosenValues() {
        let rows = TagCopy.compare(source: source, destination: destination)
        #expect(TagCopy.changes(copying: ["COMMENT", "DATE", "ARTIST", "NOPE"], in: rows) == [
            "COMMENT": ["Ripped from vinyl"], "DATE": ["1987"],
        ])
    }

    @Test func tagsHaveNames() {
        #expect(TagCopy.name(of: "ALBUMARTIST") == "Album Artist")
        #expect(TagCopy.name(of: "INITIALKEY") == "Key")
        #expect(TagCopy.name(of: "MUSICBRAINZ_TRACKID") == "MUSICBRAINZ_TRACKID")
    }

    @Test func editLogRoundTrips() throws {
        var log = TagEditLog()
        // Whole seconds, since the log keeps ISO 8601 dates.
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        log.append(TagEdit(date: date, file: URL(filePath: "/Music/a.flac"), source: URL(filePath: "/Music/a.mp3"), before: ["COMMENT": []], after: ["COMMENT": ["Ripped"]]))
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/TagEdits.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try TagEditLog.load(from: url) == TagEditLog(), "No file yet")
        try log.save(to: url)
        #expect(try TagEditLog.load(from: url) == log)
    }
}
