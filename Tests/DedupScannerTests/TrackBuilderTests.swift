import DedupCore
import Foundation
import Testing
@testable import DedupScanner

struct TrackBuilderTests {
    let file = DiscoveredFile(
        url: URL(filePath: "/Music/House/01 Song.m4a"),
        root: URL(filePath: "/Music"),
        size: 1234,
        modified: Date(timeIntervalSince1970: 1_000_000)
    )

    @Test(arguments: [
        ("3", 3), ("03", 3), ("3/12", 3), (" 7 ", 7), ("12 of 14", 12),
    ])
    func leadingNumber(input: String, expected: Int) {
        #expect(TrackBuilder.leadingNumber(in: input) == expected)
    }

    @Test(arguments: ["", "A1", "B2", "0", "0/12", "/12", "one"])
    func noLeadingNumber(input: String) {
        #expect(TrackBuilder.leadingNumber(in: input) == nil)
    }

    @Test(arguments: [
        ("1987", 1987), ("2011-05-01", 2011), ("2011-05-01T10:00:00", 2011),
        ("05/01/2011", 2011), ("20110501", 2011), ("(P) 1999 Label", 1999),
    ])
    func year(input: String, expected: Int) {
        #expect(TrackBuilder.year(in: input) == expected)
    }

    @Test(arguments: ["", "87", "May", "12/05/99"])
    func noYear(input: String) {
        #expect(TrackBuilder.year(in: input) == nil)
    }

    @Test func mapsTagsToFields() {
        let metadata = FileMetadata(
            properties: [
                "TITLE": ["Strings of Life"],
                "ARTIST": ["Rhythim Is Rhythim", "Derrick May"],
                "ALBUM": ["Innovator"],
                "ALBUMARTIST": ["Derrick May"],
                "TRACKNUMBER": ["3/12"],
                "DISCNUMBER": ["1/2"],
                "DATE": ["1987-01-01"],
                "COMMENT": ["Vinyl rip"],
                "GENRE": ["Techno"],
                "INITIALKEY": ["8A"],
            ],
            stream: StreamProperties(format: .alac, bitrate: 900, sampleRate: 44_100, channels: 2, bitDepth: 16)
        )
        let decoded = DecodedAudioInfo(duration: 391.2, format: .alac, sampleRate: 44_100, channels: 2)
        let track = TrackBuilder.track(for: file, metadata: metadata, decoded: decoded)

        #expect(track.title == "Strings of Life")
        #expect(track.artist == "Rhythim Is Rhythim; Derrick May")
        #expect(track.album == "Innovator")
        #expect(track.albumArtist == "Derrick May")
        #expect(track.trackNumber == 3)
        #expect(track.discNumber == 1)
        #expect(track.year == 1987)
        #expect(track.comment == "Vinyl rip")
        #expect(track.genre == "Techno")
        #expect(track.tags["INITIALKEY"] == "8A")
        #expect(track.tags["ARTIST"] == "Rhythim Is Rhythim; Derrick May")
        #expect(track.duration == 391.2)
        #expect(track.audio == AudioProperties(format: .alac, bitrate: 900, sampleRate: 44_100, bitDepth: 16, channels: 2))
        #expect(track.url == file.url)
        #expect(track.scanRoot == file.root)
        #expect(track.fileSize == 1234)
        #expect(track.modified == file.modified)
    }

    @Test func joinedArtistsSplitAsCollaborators() {
        let metadata = FileMetadata(properties: ["ARTIST": ["A", "B"]])
        let track = TrackBuilder.track(for: file, metadata: metadata, decoded: nil)
        #expect(CreditParser.splitCollaborators(track.artist) == ["A", "B"])
    }

    @Test func formatComesFromTagLibFirst() {
        let metadata = FileMetadata(stream: StreamProperties(format: .aac))
        let decoded = DecodedAudioInfo(duration: 1, format: .alac, sampleRate: 44_100, channels: 2)
        #expect(TrackBuilder.track(for: file, metadata: metadata, decoded: decoded).audio.format == .aac)
    }

    @Test func formatFallsBackToDecoderThenExtension() {
        let decoded = DecodedAudioInfo(duration: 1, format: .alac, sampleRate: 48_000, channels: 1)
        let fromDecoder = TrackBuilder.track(for: file, metadata: FileMetadata(stream: StreamProperties()), decoded: decoded)
        #expect(fromDecoder.audio.format == .alac)
        #expect(fromDecoder.audio.sampleRate == 48_000)
        #expect(fromDecoder.audio.channels == 1)

        let fromExtension = TrackBuilder.track(for: file, metadata: nil, decoded: nil)
        #expect(fromExtension.audio.format == .aac)
    }

    @Test func unsupportedFormatStaysUnknown() {
        let metadata = FileMetadata(stream: StreamProperties(format: .unknown))
        #expect(TrackBuilder.track(for: file, metadata: metadata, decoded: nil).audio.format == .unknown)
    }

    @Test func missingEverythingGivesEmptyTrack() {
        let track = TrackBuilder.track(for: file, metadata: nil, decoded: nil)
        #expect(track.title.isEmpty)
        #expect(track.artist.isEmpty)
        #expect(track.tags.isEmpty)
        #expect(track.duration == nil)
        #expect(track.trackNumber == nil)
        #expect(track.fileStem == "01 Song")
    }
}
