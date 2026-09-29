#if canImport(AVFoundation)
import DedupCore
import Foundation
import Testing
@testable import DedupScanner

/// End-to-end reads of real encoded audio: tags through TagLib, duration and
/// codec through Core Audio.
struct AudioFileReaderTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var fileName: String
        var format: AudioFormat
        var bitDepth: Int?
        var testDescription: String { fileName }
    }

    static let encoded: [Case] = [
        Case(fileName: "aac.m4a", format: .aac, bitDepth: nil),
        Case(fileName: "alac.m4a", format: .alac, bitDepth: 16),
        Case(fileName: "song.flac", format: .flac, bitDepth: 16),
        Case(fileName: "song.aiff", format: .aiff, bitDepth: 16),
    ]

    let tags: [String: [String]] = [
        "TITLE": ["Strings of Life (Original Mix)"],
        "ARTIST": ["Rhythim Is Rhythim"],
        "ALBUM": ["Innovator"],
        "TRACKNUMBER": ["3/12"],
        "DATE": ["1987"],
        "INITIALKEY": ["8A"],
    ]

    func discovered(_ url: URL, in folder: URL) throws -> DiscoveredFile {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return DiscoveredFile(url: url, root: folder, size: Int64(values.fileSize!), modified: values.contentModificationDate!)
    }

    @Test(arguments: encoded)
    func readsEncodedFile(_ fixture: Case) async throws {
        try await withTemporaryFolder { folder in
            let url = folder.appending(path: fixture.fileName)
            try AudioFixtures.encode(to: url, format: fixture.format, seconds: 1.5)
            try TagLibFile.write(tags, to: url)

            let result = AudioFileReader().read(try discovered(url, in: folder))
            let track = result.track
            #expect(result.problems.isEmpty)
            #expect(track.title == "Strings of Life (Original Mix)")
            #expect(track.artist == "Rhythim Is Rhythim")
            #expect(track.album == "Innovator")
            #expect(track.trackNumber == 3)
            #expect(track.year == 1987)
            #expect(track.tags["INITIALKEY"] == "8A")
            #expect(track.audio.format == fixture.format)
            #expect(track.audio.bitDepth == fixture.bitDepth)
            #expect(track.audio.sampleRate == 44_100)
            #expect(track.audio.channels == 2)
            #expect((track.audio.bitrate ?? 0) > 0)
            // Within one AAC packet (1,024 frames), in case padding isn't trimmed.
            #expect(abs((track.duration ?? 0) - 1.5) < 0.025)
        }
    }

    @Test func readsHandMadeMP3AndWAV() async throws {
        try await withTemporaryFolder { folder in
            let mp3 = folder.appending(path: "song.mp3")
            try AudioFixtures.writeMP3(to: mp3, frames: 40)
            let wav = folder.appending(path: "song.wav")
            try AudioFixtures.writeWAV(to: wav, seconds: 2)

            let mp3Track = AudioFileReader().read(try discovered(mp3, in: folder)).track
            #expect(mp3Track.audio.format == .mp3)
            #expect(abs((mp3Track.duration ?? 0) - 40 * AudioFixtures.mp3FrameDuration) < 0.05)

            let wavTrack = AudioFileReader().read(try discovered(wav, in: folder)).track
            #expect(wavTrack.audio.format == .wav)
            #expect(wavTrack.duration == 2)
        }
    }

    @Test func durationIgnoresLengthTags() async throws {
        try await withTemporaryFolder { folder in
            let url = folder.appending(path: "song.flac")
            try AudioFixtures.encode(to: url, format: .flac, seconds: 1)
            try TagLibFile.write(["LENGTH": ["999000"]], to: url)
            let track = AudioFileReader().read(try discovered(url, in: folder)).track
            #expect(abs((track.duration ?? 0) - 1) < 0.01)
        }
    }

    @Test func unreadableFileStillBecomesATrack() async throws {
        try await withTemporaryFolder { folder in
            let url = try folder.appending(path: "Artist - Title.flac").create("not audio")
            let result = AudioFileReader().read(try discovered(url, in: folder))
            #expect(result.problems == ["Couldn't read the tags.", "Couldn't decode the audio, so its duration is unknown."])
            #expect(result.track.audio.format == .flac)
            #expect(result.track.duration == nil)
            #expect(result.track.fileStem == "Artist - Title")
        }
    }

    @Test func mp3WithoutAudioKeepsItsFormat() async throws {
        try await withTemporaryFolder { folder in
            let url = try folder.appending(path: "broken.mp3").create("not audio")
            let result = AudioFileReader().read(try discovered(url, in: folder))
            #expect(result.problems == ["Couldn't decode the audio, so its duration is unknown."])
            #expect(result.track.audio.format == .mp3)
        }
    }

    @Test func scansAMixedFolderEndToEnd() async throws {
        try await withTemporaryFolder { folder in
            let root = folder.appending(path: "Music")
            try FileManager.default.createDirectory(at: root.appending(path: "Album"), withIntermediateDirectories: true)
            try AudioFixtures.encode(to: root.appending(path: "Album/01.m4a"), format: .alac, seconds: 1)
            try AudioFixtures.encode(to: root.appending(path: "Album/02.flac"), format: .flac, seconds: 1)
            try AudioFixtures.writeMP3(to: root.appending(path: "03.mp3"), frames: 40)
            try TagLibFile.write(["TITLE": ["Same Song"], "ARTIST": ["Same Artist"]], to: root.appending(path: "Album/01.m4a"))
            try TagLibFile.write(["TITLE": ["Same Song"], "ARTIST": ["Same Artist"]], to: root.appending(path: "Album/02.flac"))

            let cacheURL = folder.appending(path: "ScanCache.json")
            let first = try await LibraryScanner(cacheURL: cacheURL).scan([root])
            // Sorted by path, so "03.mp3" comes before the "Album" folder.
            #expect(first.tracks.map { $0.audio.format } == [.mp3, .alac, .flac])
            #expect(first.issues.isEmpty)

            let groups = try await MatchEngine().findDuplicates(in: first.tracks)
            #expect(groups.count == 1)
            #expect(Set(groups.first?.trackIDs ?? []) == [1, 2])

            let second = try await LibraryScanner(cacheURL: cacheURL).scan([root])
            #expect(second.cachedCount == 3)
            #expect(second.tracks == first.tracks)
        }
    }
}
#endif
