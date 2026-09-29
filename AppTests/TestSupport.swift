import AppKit
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

let downArrow = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
let upArrow = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
