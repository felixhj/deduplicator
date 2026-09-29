import DedupCore
import Foundation

/// Reads one file into a `Track`. `LibraryScanner` assigns the track's `id`.
public protocol TrackReader: Sendable {
    func read(_ file: DiscoveredFile) -> TrackReadResult
}

public struct TrackReadResult: Sendable {
    public var track: Track
    /// Problems that didn't stop the file becoming a track, such as unreadable tags.
    public var problems: [String]

    public init(track: Track, problems: [String] = []) {
        self.track = track
        self.problems = problems
    }
}

/// Reads tags and stream properties with TagLib, and on macOS the decoded
/// duration with AVFoundation. A file that fails both still becomes a track,
/// so the filename fallback can match it.
public struct AudioFileReader: TrackReader {
    public init() {}

    public func read(_ file: DiscoveredFile) -> TrackReadResult {
        var problems: [String] = []
        let metadata = try? TagLibFile.read(file.url)
        if metadata == nil {
            problems.append("Couldn't read the tags.")
        }
        var decoded: DecodedAudioInfo?
        #if canImport(AVFoundation)
        decoded = try? DecodedAudio.read(file.url)
        if decoded == nil {
            problems.append("Couldn't decode the audio, so its duration is unknown.")
        }
        #endif
        let track = TrackBuilder.track(for: file, metadata: metadata, decoded: decoded)
        return TrackReadResult(track: track, problems: problems)
    }
}
