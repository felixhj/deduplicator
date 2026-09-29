import Foundation

/// A scanned audio file with its tags already read.
///
/// `Track` is a plain value: the app's scanner fills it in, and the matching
/// engine only reads it. `duration` is always measured from the decoded
/// audio, never taken from a length tag.
public struct Track: Identifiable, Sendable, Hashable, Codable {
    public typealias ID = Int

    public var id: ID
    public var url: URL
    /// The folder the user added that this file was found under. Used to
    /// mirror folder structure when moving files.
    public var scanRoot: URL?

    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String
    public var trackNumber: Int?
    public var discNumber: Int?
    public var year: Int?
    public var comment: String
    public var genre: String

    /// Decoded duration in seconds, or nil if it could not be measured.
    public var duration: Double?
    public var audio: AudioProperties
    public var fileSize: Int64
    public var modified: Date

    /// Every tag found in the file, keyed by a display name
    /// (for example "TITLE", "TKEY", "INITIALKEY", "COMMENT").
    public var tags: [String: String]

    public init(
        id: ID,
        url: URL,
        scanRoot: URL? = nil,
        title: String = "",
        artist: String = "",
        album: String = "",
        albumArtist: String = "",
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        year: Int? = nil,
        comment: String = "",
        genre: String = "",
        duration: Double? = nil,
        audio: AudioProperties = AudioProperties(),
        fileSize: Int64 = 0,
        modified: Date = Date(timeIntervalSince1970: 0),
        tags: [String: String] = [:]
    ) {
        self.id = id
        self.url = url
        self.scanRoot = scanRoot
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.year = year
        self.comment = comment
        self.genre = genre
        self.duration = duration
        self.audio = audio
        self.fileSize = fileSize
        self.modified = modified
        self.tags = tags
    }

    /// File name without its extension, used by the filename fallback rule.
    public var fileStem: String {
        url.deletingPathExtension().lastPathComponent
    }
}

public struct AudioProperties: Sendable, Hashable, Codable {
    public var format: AudioFormat
    /// Kilobits per second.
    public var bitrate: Int?
    /// Hertz.
    public var sampleRate: Int?
    public var bitDepth: Int?
    public var channels: Int?

    public init(
        format: AudioFormat = .unknown,
        bitrate: Int? = nil,
        sampleRate: Int? = nil,
        bitDepth: Int? = nil,
        channels: Int? = nil
    ) {
        self.format = format
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channels = channels
    }

    public var isLossless: Bool { format.isLossless }
}

public enum AudioFormat: String, Sendable, Hashable, Codable, CaseIterable {
    case mp3, aac, alac, flac, aiff, wav, unknown

    public var isLossless: Bool {
        switch self {
        case .alac, .flac, .aiff, .wav: true
        case .mp3, .aac, .unknown: false
        }
    }

    public var displayName: String {
        switch self {
        case .mp3: "MP3"
        case .aac: "AAC"
        case .alac: "ALAC"
        case .flac: "FLAC"
        case .aiff: "AIFF"
        case .wav: "WAV"
        case .unknown: "Unknown"
        }
    }

    /// Best guess from the file extension. `.m4a` is ambiguous (AAC or ALAC),
    /// so the scanner should refine it from the codec.
    public init(fileExtension ext: String) {
        switch ext.lowercased() {
        case "mp3": self = .mp3
        case "m4a", "aac", "mp4": self = .aac
        case "flac": self = .flac
        case "aif", "aiff", "aifc": self = .aiff
        case "wav", "wave": self = .wav
        default: self = .unknown
        }
    }

    public static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "mp4", "flac", "aif", "aiff", "aifc", "wav", "wave",
    ]
}
