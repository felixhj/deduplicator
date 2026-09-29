import Foundation
import Testing
@testable import DedupCore

struct TrackColumnTests {
    func track(_ id: Int = 0, title: String = "Song", artist: String = "Artist") -> Track {
        Track(id: id, url: URL(filePath: "/Music/\(id) \(title).flac"), title: title, artist: artist)
    }

    @Test func idsRoundTrip() {
        for column in TrackColumn.builtIn + [.tag("INITIALKEY"), .tag("COMMENT:ITUNNORM")] {
            #expect(TrackColumn(id: column.id) == column)
        }
        #expect(TrackColumn.title.id == "title")
        #expect(TrackColumn.tag("BPM").id == "tag:BPM")
        #expect(TrackColumn(id: "tag:") == nil)
        #expect(TrackColumn(id: "nonsense") == nil)
    }

    @Test func defaultsFollowTheSpec() {
        #expect(TrackColumn.defaults.map(\.title) == [
            "#", "Title", "Artist", "Album Artist", "Album", "Year", "Comment",
            "Duration", "Bitrate", "Format", "Size", "Path",
        ])
    }

    @Test(arguments: [
        (0.4, "0:00"), (59.5, "1:00"), (225.4, "3:45"), (3723, "1:02:03"),
    ])
    func formatsDuration(seconds: Double, expected: String) {
        #expect(TrackColumn.formatDuration(seconds) == expected)
    }

    @Test(arguments: [
        (44_100, "44.1 kHz"), (48_000, "48 kHz"), (88_200, "88.2 kHz"), (192_000, "192 kHz"),
    ])
    func formatsSampleRate(hertz: Int, expected: String) {
        #expect(TrackColumn.formatSampleRate(hertz) == expected)
    }

    @Test(arguments: [
        (Int64(512), "512 bytes"), (823_400, "823 KB"), (8_249_000, "8.2 MB"), (1_234_000_000, "1.23 GB"),
    ])
    func formatsSize(bytes: Int64, expected: String) {
        #expect(TrackColumn.formatSize(bytes) == expected)
    }

    @Test func formatsDateInTheGivenTimeZone() {
        let date = Date(timeIntervalSince1970: 1_714_573_920) // 2024-05-01 14:32 UTC
        #expect(TrackColumn.formatDate(date, timeZone: TimeZone(identifier: "UTC")!) == "2024-05-01 14:32")
        #expect(TrackColumn.formatDate(date, timeZone: TimeZone(identifier: "Europe/London")!) == "2024-05-01 15:32")
    }

    @Test func textForEachKindOfField() {
        var t = track(title: "Strings of Life")
        t.trackNumber = 3
        t.duration = 391.2
        t.audio = AudioProperties(format: .flac, bitrate: 900, sampleRate: 44_100, bitDepth: 24, channels: 2)
        t.fileSize = 44_000_000
        t.tags = ["INITIALKEY": "8A"]

        #expect(TrackColumn.trackNumber.text(for: t) == "3")
        #expect(TrackColumn.year.text(for: t) == "")
        #expect(TrackColumn.duration.text(for: t) == "6:31")
        #expect(TrackColumn.bitrate.text(for: t) == "900 kbps")
        #expect(TrackColumn.format.text(for: t) == "FLAC")
        #expect(TrackColumn.sampleRate.text(for: t) == "44.1 kHz")
        #expect(TrackColumn.bitDepth.text(for: t) == "24-bit")
        #expect(TrackColumn.size.text(for: t) == "44.0 MB")
        #expect(TrackColumn.fileName.text(for: t) == "0 Strings of Life.flac")
        #expect(TrackColumn.path.text(for: t) == "/Music/0 Strings of Life.flac")
        #expect(TrackColumn.tag("INITIALKEY").text(for: t) == "8A")
        #expect(TrackColumn.tag("BPM").text(for: t) == "")
    }

    @Test func sortKeysAreNumericWhereTheyShouldBe() {
        var a = track(0), b = track(1)
        a.trackNumber = 9
        b.trackNumber = 10
        #expect(TrackColumn.trackNumber.sortKey(for: a) < TrackColumn.trackNumber.sortKey(for: b))
        #expect(TrackColumn.trackNumber.sortKey(for: track(2)) == .missing)
        #expect(TrackColumn.title.sortKey(for: track(title: "")) == .missing)
    }

    @Test func textSortsLikeTheFinder() {
        #expect(SortKey.text("track 2") < SortKey.text("Track 10"))
        #expect(SortKey.text("abba") < SortKey.text("Björk"))
        #expect(!(SortKey.text("ABBA") < SortKey.text("abba")))
        #expect(SortKey.number(5) < SortKey.missing)
        #expect(!(SortKey.missing < SortKey.number(5)))
    }
}

struct GroupDifferencesTests {
    func tracks(_ values: [String]) -> [Track] {
        values.enumerated().map { Track(id: $0.offset, url: URL(filePath: "/Music/\($0.offset).mp3"), title: "T", comment: $0.element) }
    }

    @Test func agreementHighlightsNothing() {
        #expect(GroupDifferences.tracks(differingIn: .comment, among: tracks(["x", "x", "x"])).isEmpty)
    }

    @Test func oddOneOutIsHighlighted() {
        #expect(GroupDifferences.tracks(differingIn: .comment, among: tracks(["x", "y", "x"])) == [1])
    }

    @Test func twoDisagreeingCopiesAreBothHighlighted() {
        #expect(GroupDifferences.tracks(differingIn: .comment, among: tracks(["x", "y"])) == [0, 1])
    }

    @Test func tiedValuesAreAllHighlighted() {
        #expect(GroupDifferences.tracks(differingIn: .comment, among: tracks(["x", "x", "y", "y"])) == [0, 1, 2, 3])
    }

    @Test func emptyCountsAsAValue() {
        #expect(GroupDifferences.tracks(differingIn: .comment, among: tracks(["x", "", "x"])) == [1])
    }

    @Test func pathsAreNeverHighlighted() {
        #expect(GroupDifferences.tracks(differingIn: .path, among: tracks(["x", "y"])).isEmpty)
        #expect(GroupDifferences.tracks(differingIn: .fileName, among: tracks(["x", "y"])).isEmpty)
    }

    @Test func singleTrackHasNothingToCompare() {
        #expect(GroupDifferences.tracks(differingIn: .comment, among: tracks(["x"])).isEmpty)
    }
}

struct GroupArrangementTests {
    let tracks: [Track.ID: Track] = {
        let list = [
            Track(id: 0, url: URL(filePath: "/Music/House/a.mp3"), title: "Café Del Mar", artist: "Energy 52", fileSize: 300),
            Track(id: 1, url: URL(filePath: "/Music/House/b.flac"), title: "Cafe Del Mar", artist: "Energy 52", fileSize: 900),
            Track(id: 2, url: URL(filePath: "/Music/Techno/c.mp3"), title: "Strings of Life", artist: "Derrick May", fileSize: 500),
            Track(id: 3, url: URL(filePath: "/Music/Techno/d.mp3"), title: "Strings of Life", artist: "Derrick May", fileSize: 100),
            Track(id: 4, url: URL(filePath: "/Music/Techno/e.wav"), title: "Strings of Life", artist: "", fileSize: 200),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }()

    let groups = [
        DuplicateGroup(id: 0, trackIDs: [0, 1], confidence: 0.95, reasons: [.sameTitle]),
        DuplicateGroup(id: 1, trackIDs: [2, 3, 4], confidence: 0.99, reasons: [.sameTitle]),
    ]

    func arrange(_ filter: ResultFilter = ResultFilter(), _ order: GroupOrder = .confidence) -> [DuplicateGroup] {
        GroupArrangement.arrange(groups, tracks: tracks, index: SearchIndex(tracks: tracks.values), filter: filter, order: order)
    }

    @Test func confidenceOrderPutsSurestFirst() {
        #expect(arrange().map(\.id) == [1, 0])
    }

    @Test func copiesOrderPutsBiggestFirst() {
        #expect(arrange(ResultFilter(), .copies).map(\.id) == [1, 0])
    }

    @Test func columnOrderSortsCopiesAndGroups() {
        let bySize = arrange(ResultFilter(), .column(.size, ascending: true))
        #expect(bySize.map(\.trackIDs) == [[3, 4, 2], [0, 1]])
        let bySizeDescending = arrange(ResultFilter(), .column(.size, ascending: false))
        #expect(bySizeDescending.map(\.trackIDs) == [[1, 0], [2, 4, 3]])
    }

    @Test func missingValuesStayLastInBothDirections() {
        let ascending = arrange(ResultFilter(), .column(.artist, ascending: true))
        #expect(ascending.first { $0.id == 1 }?.trackIDs.last == 4)
        let descending = arrange(ResultFilter(), .column(.artist, ascending: false))
        #expect(descending.first { $0.id == 1 }?.trackIDs.last == 4)
    }

    @Test func textFilterIgnoresCaseAndAccentsAndKeepsWholeGroups() {
        #expect(arrange(ResultFilter(text: "cafe")).map(\.id) == [0])
        #expect(arrange(ResultFilter(text: "CAFÉ")).map(\.id) == [0])
        #expect(arrange(ResultFilter(text: "e.wav")).map(\.trackIDs) == [[2, 3, 4]])
        #expect(arrange(ResultFilter(text: "  ")).count == 2)
        #expect(arrange(ResultFilter(text: "nothing like this")).isEmpty)
    }

    @Test func searchIndexAddsAndRemovesTracks() {
        var index = SearchIndex(tracks: [tracks[0]!])
        index.add([tracks[2]!])
        #expect(index.track(2, contains: "strings"))
        index.remove([0])
        #expect(!index.track(0, contains: "cafe"))
        #expect(index.track(2, contains: "strings"))
    }

    @Test func searchIndexFoldsCaseAndAccents() {
        let index = SearchIndex(tracks: tracks.values)
        #expect(index.track(0, contains: SearchIndex.fold("CAFÉ del")))
        #expect(index.track(4, contains: SearchIndex.fold("/music/techno/")))
        #expect(!index.track(2, contains: SearchIndex.fold("energy")))
        #expect(!index.track(99, contains: "a"))
    }

    @Test func confidenceFilter() {
        #expect(arrange(ResultFilter(minimumConfidence: 0.97)).map(\.id) == [1])
        #expect(arrange(ResultFilter(minimumConfidence: 1)).isEmpty)
    }
}
