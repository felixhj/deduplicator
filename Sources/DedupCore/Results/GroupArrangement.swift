import Foundation

/// Which duplicate groups to show.
public struct ResultFilter: Sendable, Hashable {
    /// Matched against title, artist, album, album artist and path, ignoring
    /// case and accents. A group is shown when any of its copies matches.
    public var text: String
    /// From 0 to 1.
    public var minimumConfidence: Double

    public init(text: String = "", minimumConfidence: Double = 0) {
        self.text = text
        self.minimumConfidence = minimumConfidence
    }

    public func includes(_ group: DuplicateGroup, index: SearchIndex) -> Bool {
        includes(group, needle: needle, index: index)
    }

    /// The text to look for, trimmed and folded for `SearchIndex`.
    var needle: String {
        SearchIndex.fold(text.trimmingCharacters(in: .whitespaces))
    }

    func includes(_ group: DuplicateGroup, needle: String, index: SearchIndex) -> Bool {
        guard group.confidence >= minimumConfidence else { return false }
        return needle.isEmpty || group.trackIDs.contains { index.track($0, contains: needle) }
    }
}

/// Each track's searchable text, with case and accents folded once up front,
/// so filtering 50,000 tracks as the user types is a plain substring search.
public struct SearchIndex: Sendable {
    private var text: [Track.ID: String] = [:]

    public init() {}

    public init(tracks: some Sequence<Track>) {
        add(tracks)
    }

    public mutating func add(_ tracks: some Sequence<Track>) {
        for track in tracks {
            let fields = [track.title, track.artist, track.album, track.albumArtist, track.url.path(percentEncoded: false)]
            text[track.id] = Self.fold(fields.joined(separator: "\n"))
        }
    }

    public mutating func remove(_ ids: some Sequence<Track.ID>) {
        for id in ids {
            text[id] = nil
        }
    }

    /// `needle` must already be folded with `fold(_:)`.
    public func track(_ id: Track.ID, contains needle: String) -> Bool {
        text[id]?.contains(needle) ?? false
    }

    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// How duplicate groups are ordered.
public enum GroupOrder: Sendable, Hashable {
    /// Most confident first.
    case confidence
    /// Groups with the most copies first.
    case copies
    /// By a column. The copies in each group are sorted the same way, and
    /// groups are ordered by their first copy.
    case column(TrackColumn, ascending: Bool)
}

public enum GroupArrangement {
    /// Filters and orders groups for display. Ties keep the engine's order.
    public static func arrange(
        _ groups: [DuplicateGroup],
        tracks: [Track.ID: Track],
        index: SearchIndex,
        filter: ResultFilter,
        order: GroupOrder
    ) -> [DuplicateGroup] {
        let needle = filter.needle
        let shown = groups.filter { filter.includes($0, needle: needle, index: index) }
        switch order {
        case .confidence:
            return stableSorted(shown) { $0.confidence > $1.confidence }
        case .copies:
            return stableSorted(shown) { $0.trackIDs.count > $1.trackIDs.count }
        case .column(let column, let ascending):
            let sorted = shown.map { sortCopies($0, by: column, ascending: ascending, tracks: tracks) }
            let firstKey = { (group: DuplicateGroup) in
                group.trackIDs.first.flatMap { tracks[$0] }.map(column.sortKey) ?? .missing
            }
            return stableSorted(sorted) { ordered(firstKey($0), firstKey($1), ascending: ascending) }
        }
    }

    static func sortCopies(_ group: DuplicateGroup, by column: TrackColumn, ascending: Bool, tracks: [Track.ID: Track]) -> DuplicateGroup {
        var group = group
        let keys = Dictionary(uniqueKeysWithValues: group.trackIDs.map { id in
            (id, tracks[id].map(column.sortKey) ?? .missing)
        })
        group.trackIDs = stableSorted(group.trackIDs) { ordered(keys[$0]!, keys[$1]!, ascending: ascending) }
        return group
    }

    /// Descending order still puts missing values last.
    static func ordered(_ a: SortKey, _ b: SortKey, ascending: Bool) -> Bool {
        if a == .missing || b == .missing { return a < b }
        return ascending ? a < b : b < a
    }

    static func stableSorted<T>(_ items: [T], by areInIncreasingOrder: (T, T) -> Bool) -> [T] {
        items.enumerated()
            .sorted { lhs, rhs in
                if areInIncreasingOrder(lhs.element, rhs.element) { return true }
                if areInIncreasingOrder(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
