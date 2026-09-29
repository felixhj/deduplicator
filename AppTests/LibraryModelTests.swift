import AVFoundation
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
            try writeSilence(to: url, seconds: 1)
            try TagLibFile.write(["TITLE": [title], "ARTIST": ["Derrick May"]], to: url)
        }

        let library = LibraryModel(defaults: storage.defaults, cacheURL: folder.appending(path: "Cache/ScanCache.json"))
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
        let library = LibraryModel(defaults: storage.defaults, cacheURL: nil)
        let music = URL(filePath: "/Music", directoryHint: .isDirectory)
        library.addFolders([music, URL(filePath: "/Music/", directoryHint: .isDirectory), URL(filePath: "/Other", directoryHint: .isDirectory)])
        #expect(library.folders.count == 2)

        let reopened = LibraryModel(defaults: storage.defaults, cacheURL: nil)
        #expect(reopened.folders.map { $0.path(percentEncoded: false) } == ["/Music/", "/Other/"])
        reopened.removeFolders([reopened.folders[0]])
        #expect(LibraryModel(defaults: storage.defaults, cacheURL: nil).folders.count == 1)
    }

    @Test func scanNeedsAFolder() {
        let library = LibraryModel(defaults: storage.defaults, cacheURL: nil)
        #expect(!library.canScan)
        library.scan()
        #expect(!library.isScanning)
    }

    /// 16-bit PCM silence, in the container the extension names.
    private func writeSilence(to url: URL, seconds: Double) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100.0, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: url.pathExtension == "aiff",
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: false)
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        try file.write(from: buffer)
        file.close()
    }
}
