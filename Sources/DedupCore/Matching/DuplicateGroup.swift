/// Why two tracks were matched. Shown in the group header.
public enum MatchReason: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case identicalTitle, sameTitle, similarTitle, fuzzyTitle
    case identicalArtist, sameArtist, similarArtist, fuzzyArtist, artistSubset
    case versionTextIgnored, featuredArtistIgnored
    case durationWithinTolerance
    case extraFieldsMatched
    case swappedTitleAndArtist

    public var description: String {
        switch self {
        case .identicalTitle: "Identical title"
        case .sameTitle: "Same title"
        case .similarTitle: "Similar title"
        case .fuzzyTitle: "Fuzzy title"
        case .identicalArtist: "Identical artist"
        case .sameArtist: "Same artist"
        case .similarArtist: "Similar artist"
        case .fuzzyArtist: "Fuzzy artist"
        case .artistSubset: "Artist credit overlaps"
        case .versionTextIgnored: "Version text ignored"
        case .featuredArtistIgnored: "Featured artist ignored"
        case .durationWithinTolerance: "Duration within tolerance"
        case .extraFieldsMatched: "Extra fields matched"
        case .swappedTitleAndArtist: "Title and artist swapped"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// A set of tracks judged to be the same recording.
public struct DuplicateGroup: Identifiable, Sendable, Hashable {
    public var id: Int
    /// The anchor comes first; the rest follow in scan order.
    public var trackIDs: [Track.ID]
    /// Mean pair score within the group, in 0...1.
    public var confidence: Double
    public var reasons: [MatchReason]

    public init(id: Int, trackIDs: [Track.ID], confidence: Double, reasons: [MatchReason]) {
        self.id = id
        self.trackIDs = trackIDs
        self.confidence = confidence
        self.reasons = reasons
    }
}
