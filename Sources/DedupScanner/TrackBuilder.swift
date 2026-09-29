import DedupCore
import Foundation

/// Builds a `Track` from what the readers found. The scanner assigns its `id`.
enum TrackBuilder {
    /// Separates the values of a tag that holds several, such as two ARTIST
    /// values in a FLAC file. `CreditParser` splits artists on it too.
    static let valueSeparator = "; "

    static func track(for file: DiscoveredFile, metadata: FileMetadata?, decoded: DecodedAudioInfo?) -> Track {
        let tags = (metadata?.properties ?? [:]).mapValues { $0.joined(separator: valueSeparator) }
        let stream = metadata?.stream
        return Track(
            id: 0,
            url: file.url,
            scanRoot: file.root,
            title: tags["TITLE"] ?? "",
            artist: tags["ARTIST"] ?? "",
            album: tags["ALBUM"] ?? "",
            albumArtist: tags["ALBUMARTIST"] ?? "",
            trackNumber: leadingNumber(in: tags["TRACKNUMBER"]),
            discNumber: leadingNumber(in: tags["DISCNUMBER"]),
            year: year(in: tags["DATE"]),
            comment: tags["COMMENT"] ?? "",
            genre: tags["GENRE"] ?? "",
            duration: decoded?.duration,
            audio: AudioProperties(
                format: stream?.format ?? decoded?.format ?? AudioFormat(fileExtension: file.url.pathExtension),
                bitrate: stream?.bitrate,
                sampleRate: stream?.sampleRate ?? decoded?.sampleRate,
                bitDepth: stream?.bitDepth,
                channels: stream?.channels ?? decoded?.channels
            ),
            fileSize: file.size,
            modified: file.modified,
            tags: tags
        )
    }

    /// The number a value starts with: "3/12" → 3, "03" → 3. Vinyl positions
    /// such as "A1", and 0, give nil.
    static func leadingNumber(in value: String?) -> Int? {
        guard let value else { return nil }
        let digits = value.drop(while: \.isWhitespace).prefix(while: \.isASCIIDigit)
        guard let number = Int(digits), number > 0 else { return nil }
        return number
    }

    /// The first run of four or more digits: "2011-05-01" and "05/01/2011" → 2011.
    static func year(in value: String?) -> Int? {
        let runs = value?.split(whereSeparator: { !$0.isASCIIDigit }) ?? []
        guard let run = runs.first(where: { $0.count >= 4 }) else { return nil }
        return Int(run.prefix(4))
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
