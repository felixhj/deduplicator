import AVFoundation
import DedupCore
import DedupScanner
import Foundation
import Observation

/// The copy in the player and whether it's playing: all the table needs for
/// its ▶ column.
struct NowPlaying: Equatable {
    var trackID: Track.ID?
    var isPlaying = false
}

/// Plays one copy at a time, so the copies in a group can be compared by ear.
/// The table puts the selected copy in the player. Selecting another copy of
/// the same track while one plays carries on from the same point.
@MainActor
@Observable
final class PlayerModel {
    /// The copy in the player, playing or not.
    private(set) var track: Track?
    private(set) var isPlaying = false
    /// Seconds from the start, kept up to date about 20 times a second while playing.
    private(set) var position: Double = 0
    /// Seconds, as the scan measured them from the decoded audio.
    private(set) var duration: Double = 0
    /// Nil until it's drawn, or if the file can't be decoded. While another
    /// copy of the same track is drawn, the old copy's waveform stays up.
    private(set) var waveform: Waveform?
    private(set) var isDrawingWaveform = false
    /// Why the copy couldn't be played, after trying.
    private(set) var failure: String?

    @ObservationIgnored private var audio: AVAudioPlayer?
    /// The copies in the track's group, the track included.
    @ObservationIgnored private var copies: [Track] = []
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var waveformTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let waveforms: WaveformCache?

    static let samePositionKey = "switchesCopiesAtSamePosition"

    /// `waveforms` keeps drawn waveforms on disk; without it, they're drawn every time.
    init(defaults: UserDefaults = .standard, waveforms: WaveformCache? = nil) {
        self.defaults = defaults
        self.waveforms = waveforms
    }

    var nowPlaying: NowPlaying {
        NowPlaying(trackID: track?.id, isPlaying: isPlaying)
    }

    /// Whether selecting another copy of the same track carries on from the
    /// same point. On unless it's switched off in Settings.
    var switchesAtSamePosition: Bool {
        defaults.object(forKey: Self.samePositionKey) as? Bool ?? true
    }

    // MARK: - Choosing a copy

    /// Puts `track` in the player, as when its row is selected. `copies` is its
    /// group. If a copy is playing, the new one plays instead: from the same
    /// point when it's another copy of the same track, otherwise from the start.
    func select(_ track: Track, copies: [Track]) {
        let previous = self.track
        self.copies = copies
        guard track.id != previous?.id else { return }
        let isAnotherCopy = previous.map { previous in copies.contains { $0.id == previous.id } } ?? false
        // Opened while the old copy plays on, so the switch is as quick as it can be.
        let next: Result<AVAudioPlayer, any Error>? = isPlaying ? Result { try Self.open(track) } : nil
        let start = isAnotherCopy && switchesAtSamePosition ? currentPosition : 0
        stopAudio()
        self.track = track
        duration = track.duration ?? 0
        position = min(start, duration)
        failure = nil
        if !isAnotherCopy { waveform = nil }
        drawWaveform()
        switch next {
        case .success(let audio): startPlaying(audio)
        case .failure: fail()
        case nil: break
        }
    }

    /// Plays `track`, putting it in the player first if it isn't there.
    func play(_ track: Track, copies: [Track]) {
        select(track, copies: copies)
        play()
    }

    /// Empties the player, for example when a new scan starts.
    func unload() {
        stopAudio()
        waveformTask?.cancel()
        track = nil
        copies = []
        position = 0
        duration = 0
        waveform = nil
        isDrawingWaveform = false
        failure = nil
    }

    // MARK: - Transport

    func play() {
        guard let track, !isPlaying else { return }
        do {
            startPlaying(try audio ?? Self.open(track))
        } catch {
            fail()
        }
    }

    func pause() {
        guard isPlaying, let audio else { return }
        audio.pause()
        position = audio.currentTime
        isPlaying = false
        ticker?.cancel()
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    /// Moves `seconds` forward, or back when negative, from where the copy is now.
    func skip(by seconds: Double) {
        seek(to: currentPosition + seconds)
    }

    /// Moves to `seconds` from the start, playing or not.
    func seek(to seconds: Double) {
        guard track != nil else { return }
        position = min(max(seconds, 0), duration)
        audio?.currentTime = position
    }

    // MARK: - Playing

    /// While playing, the audio player's own position is fresher than `position`.
    private var currentPosition: Double {
        isPlaying ? audio?.currentTime ?? position : position
    }

    private static func open(_ track: Track) throws -> AVAudioPlayer {
        let audio = try AVAudioPlayer(contentsOf: track.url)
        audio.prepareToPlay()
        return audio
    }

    private func startPlaying(_ audio: AVAudioPlayer) {
        self.audio = audio
        if track?.duration == nil { duration = audio.duration }
        // Playing from the very end would stop at once, so it starts from the top.
        if position >= duration - 0.05 { position = 0 }
        audio.currentTime = position
        guard audio.play() else {
            fail()
            return
        }
        isPlaying = true
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self else { return }
                self.tick()
            }
        }
    }

    /// Follows the playing copy, and notices when it stops by itself: at the
    /// end, where it goes back to the start, or when the system stops it.
    private func tick() {
        guard isPlaying, let audio else { return }
        position = audio.currentTime
        if !audio.isPlaying {
            isPlaying = false
            ticker?.cancel()
        }
    }

    private func stopAudio() {
        ticker?.cancel()
        ticker = nil
        audio?.stop()
        audio = nil
        isPlaying = false
    }

    private func fail() {
        stopAudio()
        let exists = track.map { FileManager.default.fileExists(atPath: $0.url.path(percentEncoded: false)) } ?? false
        failure = exists ? "This file can't be played." : "This file has moved or been deleted since the scan."
    }

    // MARK: - Waveform

    /// Draws the track's waveform in the background, then the other copies',
    /// so switching to one of them shows its waveform at once.
    private func drawWaveform() {
        waveformTask?.cancel()
        guard let track else { return }
        isDrawingWaveform = true
        let cache = waveforms
        let others = copies.filter { $0.id != track.id }
        waveformTask = Task.detached(priority: .userInitiated) { [weak self] in
            let waveform = try? PlayerModel.waveform(of: track, cache: cache)
            await self?.show(waveform, for: track.id)
            guard let cache else { return }
            for copy in others where !Task.isCancelled {
                _ = try? PlayerModel.waveform(of: copy, cache: cache)
            }
        }
    }

    /// The saved waveform, or one drawn from the file and then saved.
    nonisolated private static func waveform(of track: Track, cache: WaveformCache?) throws -> Waveform {
        if let saved = cache?.waveform(for: track) { return saved }
        let waveform = try WaveformReader.read(track.url)
        try? cache?.store(waveform, for: track)
        return waveform
    }

    private func show(_ waveform: Waveform?, for id: Track.ID) {
        guard track?.id == id else { return }
        self.waveform = waveform
        isDrawingWaveform = false
    }
}
