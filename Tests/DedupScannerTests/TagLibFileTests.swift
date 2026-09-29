import DedupCore
import Foundation
import Testing
@testable import DedupScanner

/// Round trips through the vendored TagLib, on files written by hand so these
/// run on Linux too.
struct TagLibFileTests {
    let tags: [String: [String]] = [
        "TITLE": ["Café Del Mar"],
        "ARTIST": ["Energy 52"],
        "ALBUM": ["Café Del Mar (Remixes)"],
        "TRACKNUMBER": ["3"],
        "DATE": ["1993"],
        "INITIALKEY": ["8A"],
    ]

    @Test func mp3RoundTrip() async throws {
        try await withTemporaryFolder { folder in
            let url = folder.appending(path: "song.mp3")
            try AudioFixtures.writeMP3(to: url, frames: 40)
            try TagLibFile.write(tags, to: url)

            let metadata = try TagLibFile.read(url)
            #expect(metadata.properties.filter { tags.keys.contains($0.key) } == tags)
            #expect(metadata.stream == StreamProperties(format: .mp3, bitrate: 128, sampleRate: 44_100, channels: 2, bitDepth: nil))
        }
    }

    @Test func wavRoundTrip() async throws {
        try await withTemporaryFolder { folder in
            let url = folder.appending(path: "song.wav")
            try AudioFixtures.writeWAV(to: url, seconds: 0.5)
            try TagLibFile.write(tags, to: url)

            let metadata = try TagLibFile.read(url)
            #expect(metadata.properties.filter { tags.keys.contains($0.key) } == tags)
            #expect(metadata.stream?.format == .wav)
            #expect(metadata.stream?.bitDepth == 16)
            #expect(metadata.stream?.sampleRate == 44_100)
            #expect(metadata.stream?.bitrate == 1411)
        }
    }

    @Test func writeLeavesOtherTagsAndRemovesEmptyKeys() async throws {
        try await withTemporaryFolder { folder in
            let url = folder.appending(path: "song.mp3")
            try AudioFixtures.writeMP3(to: url, frames: 10)
            try TagLibFile.write(["TITLE": ["Song"], "COMMENT": ["Old"], "GENRE": ["House"]], to: url)
            try TagLibFile.write(["COMMENT": ["New"], "GENRE": []], to: url)

            let properties = try TagLibFile.read(url).properties
            #expect(properties["TITLE"] == ["Song"])
            #expect(properties["COMMENT"] == ["New"])
            #expect(properties["GENRE"] == nil)
        }
    }

    @Test func untaggedFileHasNoProperties() async throws {
        try await withTemporaryFolder { folder in
            let url = folder.appending(path: "plain.wav")
            try AudioFixtures.writeWAV(to: url, seconds: 0.1)
            #expect(try TagLibFile.read(url).properties.isEmpty)
        }
    }

    @Test func nonAudioFileCannotBeOpened() async throws {
        try await withTemporaryFolder { folder in
            let url = try folder.appending(path: "fake.flac").create("This is a text file, not audio.")
            #expect(throws: TagLibError.cannotOpen(path: url.filePath)) { try TagLibFile.read(url) }
        }
    }

    /// TagLib opens any ".mp3" as an MPEG file, even with no audio frames in it.
    @Test func mp3WithoutAudioHasNoStream() async throws {
        try await withTemporaryFolder { folder in
            let url = try folder.appending(path: "fake.mp3").create("This is a text file, not audio.")
            #expect(try TagLibFile.read(url) == FileMetadata(properties: [:], stream: nil))
        }
    }

    @Test func missingFileCannotBeOpened() async throws {
        try await withTemporaryFolder { folder in
            let url = folder.appending(path: "missing.flac")
            #expect(throws: TagLibError.cannotOpen(path: url.filePath)) { try TagLibFile.read(url) }
        }
    }

    @Test func readOnlyFileCannotBeWritten() async throws {
        try await withTemporaryFolder { folder in
            let url = folder.appending(path: "locked.mp3")
            try AudioFixtures.writeMP3(to: url, frames: 10)
            try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.filePath)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.filePath) }

            #expect(throws: TagLibError.cannotOpen(path: url.filePath)) { try TagLibFile.write(["TITLE": ["x"]], to: url) }
            #expect(try TagLibFile.read(url).properties.isEmpty)
        }
    }

    @Test func pathsWithUnicodeWork() async throws {
        try await withTemporaryFolder { folder in
            let url = folder.appending(path: "Røyksopp – Eple (Björk’s mix).mp3")
            try AudioFixtures.writeMP3(to: url, frames: 10)
            try TagLibFile.write(["TITLE": ["Eple"]], to: url)
            #expect(try TagLibFile.read(url).properties["TITLE"] == ["Eple"])
        }
    }
}
