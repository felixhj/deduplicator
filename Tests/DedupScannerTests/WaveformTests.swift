import DedupCore
import Foundation
import Testing
@testable import DedupScanner

struct WaveformCacheTests {
    let waveform = Waveform(peaks: [0, 0.5, 1], levels: [0, 0.25, 0.5])

    func track(_ path: String = "/Music/Café/a.flac", size: Int64 = 100, modified: TimeInterval = 1_234.567_891) -> Track {
        Track(id: 0, url: URL(filePath: path), fileSize: size, modified: Date(timeIntervalSince1970: modified))
    }

    @Test func storesAndLoads() async throws {
        try await withTemporaryFolder { folder in
            let cache = WaveformCache(folder: folder.appending(path: "Nested/Waveforms", directoryHint: .isDirectory))
            #expect(cache.waveform(for: track()) == nil)
            try cache.store(waveform, for: track())
            #expect(cache.waveform(for: track()) == waveform)
        }
    }

    @Test func missesWhenTheFileChanged() async throws {
        try await withTemporaryFolder { folder in
            let cache = WaveformCache(folder: folder)
            try cache.store(waveform, for: track())
            #expect(cache.waveform(for: track(size: 101)) == nil)
            #expect(cache.waveform(for: track(modified: 1_235)) == nil)
            #expect(cache.waveform(for: track("/Music/Cafe/a.flac")) == nil)
        }
    }

    @Test func eachFileHasItsOwnEntry() {
        let cache = WaveformCache(folder: URL(filePath: "/Cache"))
        let names = [track(), track(size: 101), track(modified: 1), track("/Music/b.flac")].map { cache.url(for: $0).lastPathComponent }
        #expect(Set(names).count == 4)
        #expect(names.allSatisfy { $0.count == 21 && $0.hasSuffix(".json") })
    }

    @Test func corruptOrOldEntriesMiss() async throws {
        try await withTemporaryFolder { folder in
            let cache = WaveformCache(folder: folder)
            try cache.url(for: track()).create("{ not json")
            #expect(cache.waveform(for: track()) == nil)

            try cache.store(waveform, for: track())
            let json = try String(contentsOf: cache.url(for: track()), encoding: .utf8)
            try cache.url(for: track()).create(json.replacingOccurrences(of: #""version":1"#, with: #""version":0"#))
            #expect(cache.waveform(for: track()) == nil)
        }
    }
}

#if canImport(AVFoundation)
struct WaveformReaderTests {
    /// Within one step of the 1/255 scale waveforms are kept to.
    func expectClose(_ measured: [Float], _ expected: [Double], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(measured.count == expected.count, sourceLocation: sourceLocation)
        let far = zip(measured, expected).filter { abs(Double($0) - $1) > 1.5 / 255 }
        #expect(far.isEmpty, "measured \(measured)", sourceLocation: sourceLocation)
    }

    @Test(arguments: [AudioFormat.wav, .aiff, .flac, .alac])
    func measuresEachSliceOfALosslessFile(format: AudioFormat) async throws {
        try await withTemporaryFolder { folder in
            let url = folder.appending(path: "steps.\(format == .alac ? "m4a" : format.rawValue)")
            try AudioFixtures.encodeSteps(to: url, format: format, amplitudes: [0, 0.5, 0.25, 0.75], seconds: 0.5)
            let waveform = try WaveformReader.read(url, slices: 8)
            let expected = [0, 0, 0.5, 0.5, 0.25, 0.25, 0.75, 0.75]
            expectClose(waveform.peaks, expected)
            expectClose(waveform.levels, expected)
        }
    }

    @Test func lossyFilesKeepTheirShape() async throws {
        try await withTemporaryFolder { folder in
            let url = folder.appending(path: "steps.m4a")
            try AudioFixtures.encodeSteps(to: url, format: .aac, amplitudes: [0.05, 0.6], seconds: 1)
            let waveform = try WaveformReader.read(url, slices: 10)
            #expect(waveform.count == 10)
            let quiet = waveform.levels[1...3], loud = waveform.levels[6...8]
            #expect(quiet.allSatisfy { $0 < 0.1 } && loud.allSatisfy { $0 > 0.4 }, "levels \(waveform.levels)")
        }
    }

    @Test func silentMP3IsFlat() async throws {
        try await withTemporaryFolder { folder in
            let url = folder.appending(path: "silence.mp3")
            try AudioFixtures.writeMP3(to: url, frames: 200)
            let waveform = try WaveformReader.read(url, slices: 100)
            #expect(waveform.count == 100)
            #expect(waveform.peaks.allSatisfy { $0 == 0 })
        }
    }

    @Test func aShortFileHasASlicePerFrame() async throws {
        try await withTemporaryFolder { folder in
            let url = folder.appending(path: "short.wav")
            try AudioFixtures.writeWAV(to: url, seconds: 100.0 / 44_100)
            #expect(try WaveformReader.read(url, slices: 1_000).count == 100)

            let empty = folder.appending(path: "empty.wav")
            try AudioFixtures.writeWAV(to: empty, seconds: 0)
            #expect(try WaveformReader.read(empty).count == 0)
        }
    }

    @Test func aFileThatIsNotAudioThrows() async throws {
        try await withTemporaryFolder { folder in
            let url = try folder.appending(path: "notes.mp3").create("not audio")
            #expect(throws: (any Error).self) { try WaveformReader.read(url) }
        }
    }

    @Test func stopsWhenCancelled() async throws {
        try await withTemporaryFolder { folder in
            let url = folder.appending(path: "tone.flac")
            try AudioFixtures.encode(to: url, format: .flac, seconds: 1)
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try WaveformReader.read(url)
            }
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    /// Two minutes of each compressed format, which is what most libraries hold.
    @Test(arguments: [AudioFormat.flac, .aac])
    func aLongFileReadsQuickly(format: AudioFormat) async throws {
        try await withTemporaryFolder { folder in
            let url = folder.appending(path: "long.\(format == .aac ? "m4a" : format.rawValue)")
            try AudioFixtures.encode(to: url, format: format, seconds: 120)
            let clock = ContinuousClock()
            let elapsed = try clock.measure { _ = try WaveformReader.read(url) }
            print("Waveform of two minutes of \(format.displayName): \(elapsed)")
            #expect(elapsed < .seconds(2))
        }
    }
}
#endif
