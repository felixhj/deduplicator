internal import CTagLib
import DedupCore
import Foundation

/// Tags and stream properties that TagLib read from a file.
public struct FileMetadata: Sendable, Hashable {
    /// TagLib's unified property map, such as "TITLE", "ARTIST" or "INITIALKEY".
    /// Keys are upper case, and a key can hold several values.
    public var properties: [String: [String]]
    /// Nil when TagLib found no audio stream.
    public var stream: StreamProperties?

    public init(properties: [String: [String]] = [:], stream: StreamProperties? = nil) {
        self.properties = properties
        self.stream = stream
    }
}

/// Audio properties from a file's stream headers.
public struct StreamProperties: Sendable, Hashable {
    /// Nil when TagLib couldn't tell the codec, as in an MP4 file with an unusual one.
    public var format: AudioFormat?
    /// Kilobits per second.
    public var bitrate: Int?
    public var sampleRate: Int?
    public var channels: Int?
    /// Only set for lossless formats.
    public var bitDepth: Int?

    public init(format: AudioFormat? = nil, bitrate: Int? = nil, sampleRate: Int? = nil, channels: Int? = nil, bitDepth: Int? = nil) {
        self.format = format
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
    }
}

public enum TagLibError: Error, Hashable, Sendable {
    /// The file is missing, can't be read (or written, when writing), or isn't a format TagLib knows.
    case cannotOpen(path: String)
    /// The file's format can't store this key.
    case cannotStore(key: String)
    case saveFailed(path: String)
}

/// Reads and writes tags with TagLib.
public enum TagLibFile {
    public static func read(_ url: URL) throws -> FileMetadata {
        guard let file = open(url, writable: false) else { throw TagLibError.cannotOpen(path: url.filePath) }
        defer { ctaglib_close(file) }
        return FileMetadata(properties: properties(of: file), stream: streamProperties(of: file))
    }

    /// Replaces the values of each key in `changes`, removing keys whose list is
    /// empty, then saves the file. Other tags are left as they are.
    public static func write(_ changes: [String: [String]], to url: URL) throws {
        guard let file = open(url, writable: true) else { throw TagLibError.cannotOpen(path: url.filePath) }
        defer { ctaglib_close(file) }
        for (key, values) in changes.sorted(by: { $0.key < $1.key }) {
            let stored = withCStrings(values) { ctaglib_set_property(file, key, $0.baseAddress, $0.count) }
            guard stored else { throw TagLibError.cannotStore(key: key) }
        }
        guard ctaglib_save(file) else { throw TagLibError.saveFailed(path: url.filePath) }
    }

    private static func open(_ url: URL, writable: Bool) -> OpaquePointer? {
        url.withUnsafeFileSystemRepresentation { path in
            path.flatMap { ctaglib_open($0, writable) }
        }
    }

    private static func properties(of file: OpaquePointer) -> [String: [String]] {
        var properties: [String: [String]] = [:]
        for index in 0..<ctaglib_property_count(file) {
            let key = String(cString: ctaglib_property_key(file, index))
            properties[key] = (0..<ctaglib_property_value_count(file, index)).map {
                String(cString: ctaglib_property_value(file, index, $0))
            }
        }
        return properties
    }

    private static func streamProperties(of file: OpaquePointer) -> StreamProperties? {
        var raw = CTagLibAudioProperties()
        guard ctaglib_audio_properties(file, &raw) else { return nil }
        return StreamProperties(
            format: AudioFormat(raw.codec),
            bitrate: positive(raw.bitrate),
            sampleRate: positive(raw.sampleRate),
            channels: positive(raw.channels),
            bitDepth: positive(raw.bitsPerSample)
        )
    }

    private static func positive(_ value: Int32) -> Int? {
        value > 0 ? Int(value) : nil
    }

    /// Calls `body` with C copies of `strings` that live until it returns.
    private static func withCStrings<R>(
        _ strings: [String],
        _ body: (UnsafeBufferPointer<UnsafePointer<CChar>>) -> R
    ) -> R {
        let copies = strings.map { strdup($0)! }
        defer { copies.forEach { free($0) } }
        return copies.map { UnsafePointer($0) }.withUnsafeBufferPointer(body)
    }
}

extension AudioFormat {
    /// Nil when TagLib couldn't tell; `.unknown` for formats the app doesn't support.
    init?(_ codec: CTagLibCodec) {
        switch codec {
        case .unknown: return nil
        case .MP3: self = .mp3
        case .AAC: self = .aac
        case .ALAC: self = .alac
        case .FLAC: self = .flac
        case .AIFF: self = .aiff
        case .WAV: self = .wav
        case .other: self = .unknown
        }
    }
}
