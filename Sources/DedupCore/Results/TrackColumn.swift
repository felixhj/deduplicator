import Foundation

/// A column in the results table: one of a track's built-in fields, or any tag.
public enum TrackColumn: Hashable, Sendable {
    case trackNumber, title, artist, albumArtist, album, year, comment, genre, discNumber
    case duration, bitrate, format, sampleRate, bitDepth, channels, size, modified, fileName, path
    /// Any tag, by TagLib's property name, such as "INITIALKEY".
    case tag(String)

    /// Every built-in column, in the order the column picker lists them.
    public static let builtIn: [TrackColumn] = [
        .trackNumber, .title, .artist, .albumArtist, .album, .year, .comment, .genre, .discNumber,
        .duration, .bitrate, .format, .sampleRate, .bitDepth, .channels, .size, .modified, .fileName, .path,
    ]

    /// The columns shown until the user changes them.
    public static let defaults: [TrackColumn] = [
        .trackNumber, .title, .artist, .albumArtist, .album, .year, .comment,
        .duration, .bitrate, .format, .size, .path,
    ]

    /// A stable identifier for table columns and saved layouts, such as
    /// "title" or "tag:INITIALKEY".
    public var id: String {
        switch self {
        case .tag(let key): "tag:\(key)"
        default: String(describing: self)
        }
    }

    public init?(id: String) {
        if id.hasPrefix("tag:") {
            let key = String(id.dropFirst(4))
            guard !key.isEmpty else { return nil }
            self = .tag(key)
        } else if let column = Self.builtIn.first(where: { $0.id == id }) {
            self = column
        } else {
            return nil
        }
    }

    public var title: String {
        switch self {
        case .trackNumber: "#"
        case .title: "Title"
        case .artist: "Artist"
        case .albumArtist: "Album Artist"
        case .album: "Album"
        case .year: "Year"
        case .comment: "Comment"
        case .genre: "Genre"
        case .discNumber: "Disc"
        case .duration: "Duration"
        case .bitrate: "Bitrate"
        case .format: "Format"
        case .sampleRate: "Sample Rate"
        case .bitDepth: "Bit Depth"
        case .channels: "Channels"
        case .size: "Size"
        case .modified: "Modified"
        case .fileName: "File Name"
        case .path: "Path"
        case .tag(let key): key
        }
    }

    /// The full name, for menus and tooltips, where "#" would be too terse.
    public var name: String {
        switch self {
        case .trackNumber: "Track Number"
        case .discNumber: "Disc Number"
        default: title
        }
    }

    /// Numbers are right-aligned.
    public var isNumeric: Bool {
        switch self {
        case .trackNumber, .year, .discNumber, .duration, .bitrate, .sampleRate, .bitDepth, .channels, .size: true
        default: false
        }
    }

    /// Whether cells that differ between copies are highlighted. Every copy
    /// has its own path and file name, so highlighting those says nothing.
    public var highlightsDifferences: Bool {
        switch self {
        case .path, .fileName: false
        default: true
        }
    }

    public func text(for track: Track) -> String {
        switch self {
        case .trackNumber: track.trackNumber.map(String.init) ?? ""
        case .title: track.title
        case .artist: track.artist
        case .albumArtist: track.albumArtist
        case .album: track.album
        case .year: track.year.map(String.init) ?? ""
        case .comment: track.comment
        case .genre: track.genre
        case .discNumber: track.discNumber.map(String.init) ?? ""
        case .duration: track.duration.map(Self.formatDuration) ?? ""
        case .bitrate: track.audio.bitrate.map { "\($0) kbps" } ?? ""
        case .format: track.audio.format.displayName
        case .sampleRate: track.audio.sampleRate.map(Self.formatSampleRate) ?? ""
        case .bitDepth: track.audio.bitDepth.map { "\($0)-bit" } ?? ""
        case .channels: track.audio.channels.map(String.init) ?? ""
        case .size: Self.formatSize(track.fileSize)
        case .modified: Self.formatDate(track.modified)
        case .fileName: track.url.lastPathComponent
        case .path: track.url.path(percentEncoded: false)
        case .tag(let key): track.tags[key] ?? ""
        }
    }

    /// What the column sorts by. Numbers sort numerically; missing values sort last.
    public func sortKey(for track: Track) -> SortKey {
        func number(_ value: (some BinaryInteger)?) -> SortKey { value.map { .number(Double($0)) } ?? .missing }
        switch self {
        case .trackNumber: return number(track.trackNumber)
        case .year: return number(track.year)
        case .discNumber: return number(track.discNumber)
        case .duration: return track.duration.map(SortKey.number) ?? .missing
        case .bitrate: return number(track.audio.bitrate)
        case .sampleRate: return number(track.audio.sampleRate)
        case .bitDepth: return number(track.audio.bitDepth)
        case .channels: return number(track.audio.channels)
        case .size: return .number(Double(track.fileSize))
        case .modified: return .number(track.modified.timeIntervalSinceReferenceDate)
        default:
            let text = text(for: track)
            return text.isEmpty ? .missing : .text(text)
        }
    }

    // MARK: - Formatting

    /// "3:45", or "1:02:03" from an hour.
    static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
        let tail = String(format: "%02d", secs)
        return hours > 0 ? "\(hours):\(String(format: "%02d", minutes)):\(tail)" : "\(minutes):\(tail)"
    }

    /// "44.1 kHz", "48 kHz".
    static func formatSampleRate(_ hertz: Int) -> String {
        let kilohertz = Double(hertz) / 1000
        let text = kilohertz.rounded() == kilohertz ? String(Int(kilohertz)) : String(format: "%.1f", kilohertz)
        return "\(text) kHz"
    }

    /// Decimal units, as the Finder shows them: "823 KB", "8.2 MB", "1.23 GB".
    public static func formatSize(_ bytes: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        switch unit {
        case 0: return "\(bytes) bytes"
        case 1: return "\(Int(value.rounded())) KB"
        case 2: return String(format: "%.1f", value) + " MB"
        default: return String(format: "%.2f", value) + " " + units[unit]
        }
    }

    /// "2024-05-01 14:32", in the current time zone.
    static func formatDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: timeZone, from: date)
        return String(
            format: "%04d-%02d-%02d %02d:%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
        )
    }
}

/// A value to sort by. Missing values sort after everything else.
public enum SortKey: Hashable, Sendable, Comparable {
    case number(Double)
    case text(String)
    case missing

    public static func < (lhs: SortKey, rhs: SortKey) -> Bool {
        switch (lhs, rhs) {
        case let (.number(a), .number(b)): a < b
        case let (.text(a), .text(b)): a.compare(b, options: [.caseInsensitive, .diacriticInsensitive, .numeric]) == .orderedAscending
        case (.number, .text): true
        case (.text, .number): false
        case (.missing, _): false
        case (_, .missing): true
        }
    }
}
