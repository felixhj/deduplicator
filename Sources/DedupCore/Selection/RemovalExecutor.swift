import Foundation

/// The file operations removal needs. `LocalFileMover` is the real
/// implementation; tests use an in-memory fake.
public protocol FileMover: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    /// Moves to the Bin and returns the file's new location there.
    func trashItem(at url: URL) throws -> URL
}

/// One file that was moved.
public struct RemovalRecord: Sendable, Hashable, Codable {
    public var trackID: Track.ID
    public var original: URL
    /// Where the file ended up (in the Bin or the chosen folder).
    public var destination: URL
}

public struct RemovalFailure: Sendable, Hashable, Codable {
    public var trackID: Track.ID
    public var source: URL
    public var message: String
}

/// One press of Remove, as written to the log.
public struct RemovalOperation: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var date: Date
    public var mode: RemovalMode
    public var records: [RemovalRecord]
    public var failures: [RemovalFailure]
    /// Set once the operation has been undone.
    public var undoneAt: Date?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        mode: RemovalMode,
        records: [RemovalRecord] = [],
        failures: [RemovalFailure] = [],
        undoneAt: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.mode = mode
        self.records = records
        self.failures = failures
        self.undoneAt = undoneAt
    }
}

public struct UndoResult: Sendable, Hashable {
    public var restored: [RemovalRecord]
    public var failures: [RemovalFailure]
}

/// Carries out a removal plan and its undo. Every file operation goes
/// through here, so it's the one place that can move user files.
public struct RemovalExecutor: Sendable {
    public var mover: any FileMover

    public init(mover: any FileMover) {
        self.mover = mover
    }

    /// Moves each file. A failure is recorded and the rest carry on.
    public func execute(_ plan: [PlannedMove], mode: RemovalMode, date: Date = Date()) -> RemovalOperation {
        var operation = RemovalOperation(date: date, mode: mode)
        for move in plan {
            do {
                let destination: URL
                if let planned = move.destination {
                    try mover.createDirectory(at: planned.deletingLastPathComponent())
                    destination = RemovalPlanner.uniqueDestination(for: planned, exists: mover.fileExists)
                    try mover.moveItem(at: move.source, to: destination)
                } else {
                    destination = try mover.trashItem(at: move.source)
                }
                operation.records.append(RemovalRecord(trackID: move.trackID, original: move.source, destination: destination))
            } catch {
                operation.failures.append(RemovalFailure(trackID: move.trackID, source: move.source, message: "\(error)"))
            }
        }
        return operation
    }

    /// Moves files back to where they were. A file whose original location
    /// is occupied again isn't overwritten; it's reported as a failure.
    public func undo(_ operation: RemovalOperation) -> UndoResult {
        var result = UndoResult(restored: [], failures: [])
        for record in operation.records.reversed() {
            do {
                guard mover.fileExists(at: record.destination) else {
                    throw UndoError.missing(record.destination)
                }
                guard !mover.fileExists(at: record.original) else {
                    throw UndoError.occupied(record.original)
                }
                try mover.createDirectory(at: record.original.deletingLastPathComponent())
                try mover.moveItem(at: record.destination, to: record.original)
                result.restored.append(record)
            } catch {
                result.failures.append(RemovalFailure(trackID: record.trackID, source: record.destination, message: "\(error)"))
            }
        }
        return result
    }

    public enum UndoError: Error, CustomStringConvertible {
        case missing(URL)
        case occupied(URL)

        public var description: String {
            switch self {
            case .missing(let url): "File is no longer at \(url.path)"
            case .occupied(let url): "Another file is already at \(url.path)"
            }
        }
    }
}

#if os(macOS)
/// `FileMover` backed by `FileManager`.
public struct LocalFileMover: FileMover {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func trashItem(at url: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        guard let trashed = result as URL? else { throw CocoaError(.fileNoSuchFile) }
        return trashed
    }
}
#endif
