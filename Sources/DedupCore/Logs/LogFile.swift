import Foundation

/// Reads and writes the app's JSON logs: pretty-printed, with sorted keys and
/// ISO 8601 dates, so a person can read them.
public enum LogFile {
    /// Nil when there's no file yet. Throws when there's one that can't be read.
    public static func load<Log: Decodable>(_ type: Log.Type, from url: URL) throws -> Log? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    public static func save(_ log: some Encodable, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(log).write(to: url, options: .atomic)
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
