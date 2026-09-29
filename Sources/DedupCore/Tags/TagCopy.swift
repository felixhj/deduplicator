import Foundation

/// A tag's values in the copy tags are copied from, and in the copy they're
/// written to. Keys are TagLib's property names, such as "TITLE".
public struct TagComparison: Sendable, Hashable, Identifiable {
    public var key: String
    public var source: [String]
    public var destination: [String]

    public init(key: String, source: [String], destination: [String]) {
        self.key = key
        self.source = source
        self.destination = destination
    }

    public var id: String { key }

    /// The source has a value, and copying it would change the destination.
    public var canCopy: Bool {
        source.contains { !$0.isEmpty } && source != destination
    }

    /// Worth copying without being asked: a tag describing the music that the
    /// destination doesn't have. Tags about the file, such as encoder
    /// settings or loudness, never are.
    public var fillsGap: Bool {
        canCopy && TagCopy.isDescriptive(key) && !destination.contains { !$0.isEmpty }
    }
}

/// Works out what copying tags from one copy of a track to another changes.
public enum TagCopy {
    /// Tags that describe the music rather than the file, in the order
    /// they're listed, with their names.
    static let descriptive: [(key: String, name: String)] = [
        ("TITLE", "Title"), ("ARTIST", "Artist"), ("ALBUMARTIST", "Album Artist"), ("ALBUM", "Album"),
        ("SUBTITLE", "Subtitle"), ("TRACKNUMBER", "Track Number"), ("DISCNUMBER", "Disc Number"),
        ("DATE", "Date"), ("ORIGINALDATE", "Original Date"), ("GENRE", "Genre"), ("COMMENT", "Comment"),
        ("COMPOSER", "Composer"), ("LYRICIST", "Lyricist"), ("CONDUCTOR", "Conductor"), ("REMIXER", "Remixer"),
        ("BPM", "BPM"), ("INITIALKEY", "Key"), ("MOOD", "Mood"), ("GROUPING", "Grouping"),
        ("LABEL", "Label"), ("CATALOGNUMBER", "Catalogue Number"), ("ISRC", "ISRC"), ("COPYRIGHT", "Copyright"),
        ("COMPILATION", "Compilation"), ("WORK", "Work"), ("MOVEMENTNAME", "Movement"), ("LYRICS", "Lyrics"),
        ("TITLESORT", "Sort Title"), ("ARTISTSORT", "Sort Artist"), ("ALBUMARTISTSORT", "Sort Album Artist"),
        ("ALBUMSORT", "Sort Album"), ("COMPOSERSORT", "Sort Composer"),
    ]

    private static let ranks = Dictionary(uniqueKeysWithValues: descriptive.enumerated().map { ($1.key, $0) })
    private static let names = Dictionary(uniqueKeysWithValues: descriptive.map { ($0.key, $0.name) })

    public static func isDescriptive(_ key: String) -> Bool {
        ranks[key] != nil
    }

    /// "Album Artist" for "ALBUMARTIST"; keys without a name stay as they are.
    public static func name(of key: String) -> String {
        names[key] ?? key
    }

    /// Every tag either copy has: the descriptive ones first, in the usual
    /// order, then the rest alphabetically.
    public static func compare(source: [String: [String]], destination: [String: [String]]) -> [TagComparison] {
        Set(source.keys).union(destination.keys)
            .sorted { lhs, rhs in
                switch (ranks[lhs], ranks[rhs]) {
                case let (a?, b?): a < b
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): lhs < rhs
                }
            }
            .map { TagComparison(key: $0, source: source[$0] ?? [], destination: destination[$0] ?? []) }
    }

    /// What to write to the destination to copy `keys` from the source.
    public static func changes(copying keys: Set<String>, in comparisons: [TagComparison]) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: comparisons.filter { keys.contains($0.key) && $0.canCopy }.map { ($0.key, $0.source) })
    }
}

/// One write of copied tags, as logged: the file written, where the values
/// came from, and each changed tag's values before and after.
public struct TagEdit: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var date: Date
    public var file: URL
    public var source: URL
    public var before: [String: [String]]
    public var after: [String: [String]]

    public init(id: UUID = UUID(), date: Date = Date(), file: URL, source: URL, before: [String: [String]], after: [String: [String]]) {
        self.id = id
        self.date = date
        self.file = file
        self.source = source
        self.before = before
        self.after = after
    }
}

/// Every write of copied tags, stored as JSON. Newest last.
public struct TagEditLog: Sendable, Hashable, Codable {
    public var edits: [TagEdit]

    public init(edits: [TagEdit] = []) {
        self.edits = edits
    }

    public mutating func append(_ edit: TagEdit) {
        edits.append(edit)
    }

    public static func load(from url: URL) throws -> TagEditLog {
        try LogFile.load(TagEditLog.self, from: url) ?? TagEditLog()
    }

    public func save(to url: URL) throws {
        try LogFile.save(self, to: url)
    }
}
