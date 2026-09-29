import Foundation

/// Every removal operation, stored as JSON. Newest last.
public struct RemovalLog: Sendable, Hashable, Codable {
    public var operations: [RemovalOperation] = []

    public init(operations: [RemovalOperation] = []) {
        self.operations = operations
    }

    /// The most recent operation that moved something and hasn't been undone.
    public var lastUndoable: RemovalOperation? {
        operations.last { $0.undoneAt == nil && !$0.records.isEmpty }
    }

    public mutating func append(_ operation: RemovalOperation) {
        operations.append(operation)
    }

    /// Records the undo, with the files it couldn't put back. An operation is
    /// undone once, even if some files failed: they're usually gone for good,
    /// as when the Bin has been emptied, and the log says where they were.
    public mutating func markUndone(_ id: RemovalOperation.ID, at date: Date = Date(), failures: [RemovalFailure] = []) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[index].undoneAt = date
        operations[index].undoFailures = failures
    }

    public static func load(from url: URL) throws -> RemovalLog {
        guard FileManager.default.fileExists(atPath: url.path) else { return RemovalLog() }
        let data = try Data(contentsOf: url)
        return try decoder.decode(RemovalLog.self, from: data)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(self).write(to: url, options: .atomic)
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
