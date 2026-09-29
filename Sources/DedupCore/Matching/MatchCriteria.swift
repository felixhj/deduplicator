/// How strictly a field must agree.
public enum MatchLevel: String, Sendable, Hashable, Codable, CaseIterable {
    /// Raw tag text is equal (whitespace trimmed, nothing else).
    case identical
    /// Normalised text is equal.
    case same
    /// Normalised text is close in spelling (Levenshtein ratio ≥ threshold).
    case similar
    /// Normalised text is loosely alike (Jaro-Winkler or word-order-insensitive ratio ≥ threshold).
    case fuzzy
    /// The field isn't compared.
    case ignore

    public var defaultThreshold: Double {
        switch self {
        case .similar: 0.9
        case .fuzzy: 0.8
        case .identical, .same, .ignore: 1
        }
    }

    /// Identical and Same need equal keys, so blocking can bucket exactly.
    var isExact: Bool { self == .identical || self == .same }
}

public struct FieldRule: Sendable, Hashable, Codable {
    public var level: MatchLevel
    /// Used by `.similar` and `.fuzzy`.
    public var threshold: Double

    public init(_ level: MatchLevel, threshold: Double? = nil) {
        self.level = level
        self.threshold = threshold ?? level.defaultThreshold
    }
}

/// Same / different / don't care, for constraints such as track number.
public enum Comparison: String, Sendable, Hashable, Codable, CaseIterable {
    case any, same, different

    func accepts<T: Equatable>(_ a: T, _ b: T) -> Bool {
        switch self {
        case .any: true
        case .same: a == b
        case .different: a != b
        }
    }
}

/// Additional tags that can be used as match criteria.
public enum TagField: String, Sendable, Hashable, Codable, CaseIterable {
    case album, albumArtist, year, genre, comment

    public func value(in track: Track) -> String {
        switch self {
        case .album: track.album
        case .albumArtist: track.albumArtist
        case .year: track.year.map(String.init) ?? ""
        case .genre: track.genre
        case .comment: track.comment
        }
    }
}

public struct ExtraFieldRule: Sendable, Hashable, Codable {
    public var field: TagField
    public var rule: FieldRule

    public init(_ field: TagField, _ rule: FieldRule) {
        self.field = field
        self.rule = rule
    }
}

/// Everything that decides whether two tracks are duplicates.
public struct MatchCriteria: Sendable, Hashable, Codable {
    public var normalisation = NormalisationOptions()

    public var title = FieldRule(.same)
    public var artist = FieldRule(.same)
    /// `A` matches `A & B` when every artist on one side appears on the other.
    public var artistSubsetMatches = false
    public var extraFields: [ExtraFieldRule] = []

    /// Maximum difference in decoded duration, in seconds. `nil` switches the check off.
    /// Tracks whose duration couldn't be measured always pass.
    public var durationTolerance: Double? = 3
    public var trackNumber: Comparison = .any
    public var album: Comparison = .any
    public var format: Comparison = .any

    /// Also match when one file has title and artist the wrong way round.
    public var detectSwappedFields = false
    /// Every member of a group must match the group's anchor directly, which
    /// stops A≈B≈C chains from joining A to a very different C.
    public var requireAnchorMatch = true

    public init() {}
}

public extension MatchCriteria {
    /// Normalised title and artist must be equal, with durations within 3 s.
    static let standard = MatchCriteria()

    static var djLibrary: MatchCriteria {
        var c = MatchCriteria()
        c.normalisation = .djLibrary
        c.title = FieldRule(.similar)
        return c
    }

    static var loose: MatchCriteria {
        var c = MatchCriteria()
        c.normalisation = .aggressive
        c.title = FieldRule(.fuzzy)
        c.artist = FieldRule(.fuzzy)
        c.artistSubsetMatches = true
        c.durationTolerance = 10
        c.detectSwappedFields = true
        return c
    }
}
