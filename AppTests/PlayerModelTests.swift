import AppKit
import DedupCore
import DedupScanner
import Foundation
import SwiftUI
import Testing
@testable import Deduplicator

/// The player, with real audio files. Files that play are silent.
@MainActor
struct PlayerModelTests {
    let storage = TestDefaults()
    let folder = TemporaryFolder()

    /// The fixture library as two-second files. Its groups are [0, 1, 2] and [3, 4].
    func makePlayer() throws -> (PlayerModel, [Track]) {
        (PlayerModel(defaults: storage.defaults), try Fixtures.playableLibrary(in: folder.url))
    }

    func copies(_ tracks: [Track], of id: Track.ID) -> [Track] {
        id < 3 ? Array(tracks[0...2]) : Array(tracks[3...4])
    }

    @Test func selectingACopyPutsItInThePlayerPaused() throws {
        let (player, tracks) = try makePlayer()
        #expect(player.nowPlaying == NowPlaying(trackID: nil, isPlaying: false))
        player.select(tracks[0], copies: copies(tracks, of: 0))
        #expect(player.nowPlaying == NowPlaying(trackID: 0, isPlaying: false))
        #expect(player.position == 0)
        #expect(player.duration == 2)
        #expect(player.failure == nil)
    }

    @Test func playsPausesAndSeeks() async throws {
        let (player, tracks) = try makePlayer()
        player.togglePlayback()
        #expect(!player.isPlaying, "Nothing to play yet")

        player.select(tracks[0], copies: copies(tracks, of: 0))
        player.seek(to: 0.5)
        #expect(player.position == 0.5)
        player.togglePlayback()
        #expect(player.isPlaying)
        try await Task.sleep(for: .milliseconds(250))
        #expect(player.position > 0.6, "The position follows the playing copy")

        player.togglePlayback()
        #expect(!player.isPlaying)
        let paused = player.position
        try await Task.sleep(for: .milliseconds(100))
        #expect(player.position == paused)
        player.seek(to: 99)
        #expect(player.position == 2, "Seeking stops at the end")
    }

    @Test func skippingMovesFromWhereTheCopyIs() throws {
        let (player, tracks) = try makePlayer()
        player.select(tracks[0], copies: copies(tracks, of: 0))
        player.seek(to: 0.5)
        player.skip(by: 1)
        #expect(player.position == 1.5)
        player.skip(by: -10)
        #expect(player.position == 0)
    }

    @Test func anotherCopyOfTheSameTrackCarriesOnFromTheSamePoint() async throws {
        let (player, tracks) = try makePlayer()
        let group = copies(tracks, of: 0)
        player.select(tracks[0], copies: group)
        player.seek(to: 0.5)
        player.select(tracks[1], copies: group)
        #expect(player.nowPlaying == NowPlaying(trackID: 1, isPlaying: false))
        #expect(player.position == 0.5)

        player.play()
        try await Task.sleep(for: .milliseconds(150))
        player.select(tracks[2], copies: group)
        #expect(player.nowPlaying == NowPlaying(trackID: 2, isPlaying: true))
        #expect(player.position > 0.55 && player.position < 1.5)
        player.pause()
    }

    @Test func anotherTrackStartsFromTheTop() throws {
        let (player, tracks) = try makePlayer()
        player.select(tracks[0], copies: copies(tracks, of: 0))
        player.seek(to: 0.5)
        player.play()
        player.select(tracks[3], copies: copies(tracks, of: 3))
        #expect(player.nowPlaying == NowPlaying(trackID: 3, isPlaying: true))
        #expect(player.position == 0)
        player.pause()
    }

    @Test func keepingThePointCanBeSwitchedOff() throws {
        let (player, tracks) = try makePlayer()
        #expect(player.switchesAtSamePosition)
        storage.defaults.set(false, forKey: PlayerModel.samePositionKey)
        #expect(!player.switchesAtSamePosition)
        player.select(tracks[0], copies: copies(tracks, of: 0))
        player.seek(to: 0.5)
        player.select(tracks[1], copies: copies(tracks, of: 1))
        #expect(player.position == 0)
    }

    @Test func playingToTheEndStopsAtTheStart() async throws {
        let (player, _) = try makePlayer()
        let url = folder.url.appending(path: "short.wav")
        try AudioFiles.write(to: url, seconds: 0.3)
        let short = Track(id: 9, url: url, duration: 0.3)
        player.play(short, copies: [short])
        #expect(player.isPlaying)
        try await waitUntil("the end") { !player.isPlaying }
        #expect(player.position == 0)
        player.play()
        #expect(player.isPlaying, "It plays again from the start")
        player.pause()
    }

    @Test func filesThatCantBePlayedSaySo() throws {
        let (player, tracks) = try makePlayer()
        let missing = Fixtures.library[5]
        player.play(missing, copies: [missing])
        #expect(!player.isPlaying)
        #expect(player.failure == "This file has moved or been deleted since the scan.")

        let text = folder.url.appending(path: "notes.wav")
        try Data("not audio".utf8).write(to: text)
        let notAudio = Track(id: 8, url: text, duration: 1)
        player.play(notAudio, copies: [notAudio])
        #expect(player.failure == "This file can't be played.")

        // Switching from a playing copy to one that can't play stops.
        player.play(tracks[0], copies: copies(tracks, of: 0))
        #expect(player.isPlaying && player.failure == nil)
        var broken = tracks[1]
        broken.url = text
        player.select(broken, copies: [tracks[0], broken])
        #expect(!player.isPlaying)
        #expect(player.failure == "This file can't be played.")
    }

    @Test func drawsWaveformsAndKeepsThemOnDisk() async throws {
        let tracks = try Fixtures.playableLibrary(in: folder.url, seconds: 1) { $0 < 0.5 ? 0.2 : 0.8 }
        let cache = WaveformCache(folder: folder.url.appending(path: "Waveforms", directoryHint: .isDirectory))
        let player = PlayerModel(defaults: storage.defaults, waveforms: cache)
        player.select(tracks[3], copies: copies(tracks, of: 3))
        #expect(player.isDrawingWaveform)
        try await waitUntil("the waveform") { !player.isDrawingWaveform }
        let waveform = try #require(player.waveform)
        #expect(waveform.count == 1_000)
        #expect(abs(waveform.peaks[0] - 0.2) < 0.01 && abs(waveform.peaks[999] - 0.8) < 0.01)
        #expect(cache.waveform(for: tracks[3]) == waveform)

        // The other copy is drawn in advance, and its old waveform stays up until then.
        try await waitUntil("the other copy's waveform") { cache.waveform(for: tracks[4]) != nil }
        player.select(tracks[4], copies: copies(tracks, of: 4))
        #expect(player.waveform == waveform)
        try await waitUntil("the other copy's waveform") { !player.isDrawingWaveform }

        // Another track's waveform replaces it.
        player.select(tracks[0], copies: copies(tracks, of: 0))
        #expect(player.waveform == nil)
    }

    @Test func closingTheResultsPauses() async throws {
        let library = LibraryModel(defaults: storage.defaults, cacheURL: nil, waveformFolder: nil, removalLog: nil)
        let tracks = try Fixtures.playableLibrary(in: folder.url)
        library.results.load(tracks)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let summary = ScanSummary(result: ScanResult(tracks: tracks), elapsed: .zero)
        window.contentView = NSHostingView(rootView: ResultsView(summary: summary).environment(library))
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        library.player.play(tracks[0], copies: Array(tracks[0...2]))
        #expect(library.player.isPlaying)
        window.contentView = nil
        try await waitUntil("the player to pause") { !library.player.isPlaying }
        #expect(library.player.track?.id == 0, "The copy stays in the player")
    }

    @Test func unloadingEmptiesThePlayer() throws {
        let (player, tracks) = try makePlayer()
        player.play(tracks[0], copies: copies(tracks, of: 0))
        player.unload()
        #expect(player.nowPlaying == NowPlaying(trackID: nil, isPlaying: false))
        #expect(player.duration == 0 && player.waveform == nil && player.failure == nil)
    }
}
