import Foundation

/// One step in deciding which copy of a track to keep.
public enum KeeperRule: Sendable, Hashable, Codable {
    case preferLossless
    case higherBitrate
    case higherSampleRate
    case higherBitDepth
    case longerDuration
    case moreTagsFilled
    case largerFile
    case olderFile
    case newerFile
    /// Prefer files whose path contains the text (case-insensitive).
    case pathContains(String)
    /// Prefer files whose path does not contain the text (case-insensitive).
    case pathDoesNotContain(String)
    case preferFormat(AudioFormat)

    /// The rules that need no text or format, which a list of rules has at most once.
    public static let plainRules: [KeeperRule] = [
        .preferLossless, .higherBitrate, .higherSampleRate, .higherBitDepth, .longerDuration,
        .moreTagsFilled, .largerFile, .olderFile, .newerFile,
    ]

    public var description: String {
        switch self {
        case .preferLossless: "Prefer lossless"
        case .higherBitrate: "Higher bitrate"
        case .higherSampleRate: "Higher sample rate"
        case .higherBitDepth: "Higher bit depth"
        case .longerDuration: "Longer duration"
        case .moreTagsFilled: "More tags filled in"
        case .largerFile: "Larger file"
        case .olderFile: "Older file"
        case .newerFile: "Newer file"
        case .pathContains(let text): "Path contains “\(text)”"
        case .pathDoesNotContain(let text): "Path doesn't contain “\(text)”"
        case .preferFormat(let format): "Prefer \(format.displayName)"
        }
    }

    /// A value where higher is better, or nil if the track doesn't have the property.
    func rank(_ track: Track) -> Double? {
        switch self {
        case .preferLossless: track.audio.isLossless ? 1 : 0
        case .higherBitrate: track.audio.bitrate.map(Double.init)
        case .higherSampleRate: track.audio.sampleRate.map(Double.init)
        case .higherBitDepth: track.audio.bitDepth.map(Double.init)
        case .longerDuration: track.duration
        case .moreTagsFilled: Double(Self.filledTagCount(track))
        case .largerFile: Double(track.fileSize)
        case .olderFile: -track.modified.timeIntervalSince1970
        case .newerFile: track.modified.timeIntervalSince1970
        case .pathContains(let text): Self.path(track).contains(text.lowercased()) ? 1 : 0
        case .pathDoesNotContain(let text): Self.path(track).contains(text.lowercased()) ? 0 : 1
        case .preferFormat(let format): track.audio.format == format ? 1 : 0
        }
    }

    /// Durations within this many seconds count as equal, so a rounding
    /// difference doesn't decide the keeper.
    var tolerance: Double {
        switch self {
        case .longerDuration: 0.5
        default: 0
        }
    }

    static func path(_ track: Track) -> String {
        track.url.path.lowercased()
    }

    static func filledTagCount(_ track: Track) -> Int {
        let core = [track.title, track.artist, track.album, track.albumArtist, track.comment, track.genre]
            .filter { !$0.isEmpty }.count
        let numbers = [track.trackNumber, track.discNumber, track.year].compactMap { $0 }.count
        let others = track.tags.values.filter { !$0.isEmpty }.count
        return core + numbers + others
    }
}

/// Chooses the copy to keep in each group and marks the rest for removal.
public struct KeeperSelector: Sendable, Hashable, Codable {
    public var rules: [KeeperRule]

    public static let defaultRules: [KeeperRule] = [
        .preferLossless, .higherBitrate, .higherSampleRate, .higherBitDepth, .longerDuration, .moreTagsFilled,
    ]

    public init(rules: [KeeperRule] = KeeperSelector.defaultRules) {
        self.rules = rules
    }

    /// The best track under the rules, applied in order. Ties go to the
    /// earlier track in the list (the group's anchor comes first).
    public func keeper(among tracks: [Track]) -> Track? {
        guard var best = tracks.first else { return nil }
        for candidate in tracks.dropFirst() where isBetter(candidate, than: best) {
            best = candidate
        }
        return best
    }

    /// True when `a` beats `b` on the first rule that separates them.
    public func isBetter(_ a: Track, than b: Track) -> Bool {
        for rule in rules {
            // A missing value ranks below any known value.
            switch (rule.rank(a), rule.rank(b)) {
            case (nil, nil): continue
            case (.some, nil): return true
            case (nil, .some): return false
            case let (ra?, rb?):
                if abs(ra - rb) <= rule.tolerance { continue }
                return ra > rb
            }
        }
        return false
    }

    /// The keeper of each group, and the copies it beats.
    public func choices(for groups: [DuplicateGroup], tracks: [Track.ID: Track]) -> [KeeperChoice] {
        groups.compactMap { group in
            let members = group.trackIDs.compactMap { tracks[$0] }
            guard let keep = keeper(among: members) else { return nil }
            return KeeperChoice(groupID: group.id, keeper: keep.id, others: members.map(\.id).filter { $0 != keep.id })
        }
    }

    /// IDs to remove across all groups: every member except each group's keeper.
    public func autoSelect(groups: [DuplicateGroup], tracks: [Track.ID: Track]) -> Set<Track.ID> {
        Set(choices(for: groups, tracks: tracks).flatMap(\.others))
    }
}

/// The copy auto-select keeps in a group, and the others, which it marks.
public struct KeeperChoice: Sendable, Hashable {
    public var groupID: DuplicateGroup.ID
    public var keeper: Track.ID
    public var others: [Track.ID]

    public init(groupID: DuplicateGroup.ID, keeper: Track.ID, others: [Track.ID]) {
        self.groupID = groupID
        self.keeper = keeper
        self.others = others
    }
}
