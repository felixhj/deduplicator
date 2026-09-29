import AppKit
import AVFoundation
import DedupCore
import Foundation
import Testing
@testable import Deduplicator

/// Settings for one test, kept in memory, so tests never touch the app's real
/// settings or leave preference files behind.
final class TestDefaults {
    let defaults: UserDefaults = InMemoryDefaults()
}

/// User defaults that live only in memory. The typed getters, such as
/// `data(forKey:)`, all read through `object(forKey:)`.
final class InMemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]

    init() {
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? {
        values[defaultName]
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }

    override func removeObject(forKey defaultName: String) {
        values[defaultName] = nil
    }
}

enum Fixtures {
    static func track(
        _ id: Track.ID,
        _ title: String,
        _ artist: String,
        format: AudioFormat = .mp3,
        bitrate: Int = 320,
        size: Int64 = 10_000_000,
        comment: String = "",
        tags: [String: String] = [:]
    ) -> Track {
        Track(
            id: id,
            url: URL(filePath: "/Music/\(artist)/\(id) \(title).\(format.rawValue)"),
            scanRoot: URL(filePath: "/Music"),
            title: title,
            artist: artist,
            album: "Album",
            trackNumber: 1,
            year: 1987,
            comment: comment,
            duration: 300,
            audio: AudioProperties(format: format, bitrate: bitrate, sampleRate: 44_100, channels: 2),
            fileSize: size,
            tags: tags
        )
    }

    /// Two groups under the standard settings, plus a track with no duplicate.
    static let library: [Track] = [
        track(0, "Strings of Life", "Derrick May", format: .flac, bitrate: 1000, size: 50_000_000, tags: ["INITIALKEY": "8A"]),
        track(1, "Strings Of Life", "Derrick May", tags: ["INITIALKEY": "8A"]),
        track(2, "Strings of Life", "Derrick May", format: .aac, bitrate: 256, comment: "Ripped"),
        track(3, "Café Del Mar", "Energy 52", format: .alac, bitrate: 900, size: 40_000_000),
        track(4, "Café Del Mar", "Energy 52"),
        track(5, "Unique", "Nobody"),
    ]
}

extension Fixtures {
    /// `library`, with a real file for each track in `folder` so it can be
    /// played: silence, unless `loudness` is given (see `AudioFiles.write`).
    static func playableLibrary(in folder: URL, seconds: Double = 2, loudness: ((Double) -> Double)? = nil) throws -> [Track] {
        let original = folder.appending(path: "original.wav")
        try AudioFiles.write(to: original, seconds: seconds, loudness: loudness)
        return try library.map { track in
            var track = track
            track.url = folder.appending(path: "\(track.id) \(track.title).wav")
            track.scanRoot = folder
            track.duration = seconds
            try FileManager.default.copyItem(at: original, to: track.url)
            return track
        }
    }
}

/// Moves files as the app does, except that its Bin is a folder of the test's own.
struct TestMover: FileMover {
    let bin: URL
    /// Seconds each move takes, as if the files were large.
    var delay: TimeInterval = 0
    private let local = LocalFileMover()

    init(bin: URL, delay: TimeInterval = 0) {
        self.bin = bin
        self.delay = delay
    }

    func fileExists(at url: URL) -> Bool { local.fileExists(at: url) }

    func createDirectory(at url: URL) throws { try local.createDirectory(at: url) }

    func moveItem(at source: URL, to destination: URL) throws {
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        try local.moveItem(at: source, to: destination)
    }

    func trashItem(at url: URL) throws -> URL {
        try local.createDirectory(at: bin)
        let destination = RemovalPlanner.uniqueDestination(for: bin.appending(path: url.lastPathComponent), exists: local.fileExists)
        try moveItem(at: url, to: destination)
        return destination
    }
}

/// A folder that lasts as long as the test that made it.
final class TemporaryFolder {
    let url = FileManager.default.temporaryDirectory.appending(path: "DeduplicatorAppTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

enum AudioFiles {
    /// 16-bit PCM, in the container the extension names. It's silent unless
    /// `loudness` is given: then it's a square wave whose amplitude, from 0 to
    /// 1, follows `loudness` of the time in seconds.
    static func write(to url: URL, seconds: Double, loudness: ((Double) -> Double)? = nil) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100.0, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: url.pathExtension == "aiff",
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: false)
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        if let loudness, let channels = buffer.int16ChannelData {
            for frame in 0..<Int(frames) {
                let sign: Double = frame % 100 < 50 ? 1 : -1
                let sample = Int16(sign * min(max(loudness(Double(frame) / 44_100), 0), 1) * Double(Int16.max))
                for channel in 0..<Int(buffer.format.channelCount) {
                    channels[channel][frame] = sample
                }
            }
        }
        try file.write(from: buffer)
        file.close()
    }
}

/// Waits until `condition` holds, for up to five seconds.
@MainActor
func waitUntil(_ what: String, _ condition: () -> Bool) async throws {
    for _ in 0..<500 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Waited five seconds for \(what)")
}

@MainActor
func waitForMatching(_ model: ResultsModel) async throws {
    for _ in 0..<500 {
        if model.matchState == .finished { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Matching didn't finish within five seconds")
}

/// A key press, as the outline view would receive it.
func keyEvent(_ characters: String, modifiers: NSEvent.ModifierFlags = [], keyCode: UInt16 = 0) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
        context: nil, characters: characters, charactersIgnoringModifiers: characters,
        isARepeat: false, keyCode: keyCode
    )!
}

/// A mouse event at a point in `window`'s coordinates.
@MainActor
func mouseEvent(_ type: NSEvent.EventType, at location: NSPoint, in window: NSWindow) -> NSEvent {
    if type == .mouseEntered || type == .mouseExited {
        return NSEvent.enterExitEvent(
            with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        )!
    }
    return NSEvent.mouseEvent(
        with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
        context: nil, eventNumber: 0, clickCount: 0, pressure: 0
    )!
}

let downArrow = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
let upArrow = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
