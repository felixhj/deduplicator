import Foundation

/// Finds duplicate groups in a set of tracks.
///
/// The pipeline:
/// 1. **Prepare:** normalise every track once.
/// 2. **Block:** bucket tracks by a key that any matching pair must share,
///    so only a small fraction of the n² pairs are compared.
/// 3. **Compare:** check constraints and fields for each candidate pair in
///    parallel. Each pair is compared once, in its first shared bucket.
/// 4. **Group:** merge matched pairs with union-find, then split chains so
///    every member matches the group's anchor.
public struct MatchEngine: Sendable {
    public var criteria: MatchCriteria
    /// Buckets bigger than this are split further by a secondary key.
    public var maxBucketSize: Int

    public typealias ProgressHandler = @Sendable (Double) -> Void

    public init(criteria: MatchCriteria = .standard, maxBucketSize: Int = 400) {
        self.criteria = criteria
        self.maxBucketSize = maxBucketSize
    }

    public func findDuplicates(in tracks: [Track], progress: ProgressHandler? = nil) async throws -> [DuplicateGroup] {
        let prepared = prepare(tracks)
        try Task.checkCancellation()
        guard let blocking = Blocking(criteria: criteria) else { return [] }
        let buckets = makeBuckets(prepared, blocking: blocking)
        try Task.checkCancellation()
        let edges = try await compare(buckets: buckets, prepared: prepared, progress: progress)
        return group(edges: edges, prepared: prepared)
    }

    /// Compares two tracks directly, with no blocking. Returns nil when they don't match.
    public func match(_ a: Track, _ b: Track) -> (score: Double, reasons: [MatchReason])? {
        let p = prepare([a, b])
        guard let edge = Self.compare(p[0], p[1], criteria: criteria) else { return nil }
        return (edge.score, edge.reasons.sorted())
    }

    // MARK: - Prepare

    struct FieldView: Sendable {
        let rawTitle: String
        let rawArtist: String
        let tags: NormalisedTags
    }

    struct PreparedTrack: Sendable {
        let index: Int
        let track: Track
        let normal: FieldView
        let swapped: FieldView?
        let album: String
        let extrasRaw: [String]
        let extrasFolded: [String]
    }

    func prepare(_ tracks: [Track]) -> [PreparedTrack] {
        let normaliser = Normaliser(options: criteria.normalisation)
        return tracks.enumerated().map { index, track in
            let rawTitle = TextFolding.collapseWhitespace(track.title)
            let rawArtist = TextFolding.collapseWhitespace(track.artist)
            let normal = FieldView(rawTitle: rawTitle, rawArtist: rawArtist, tags: normaliser.normalise(track))
            let swapped = criteria.detectSwappedFields
                ? FieldView(
                    rawTitle: rawArtist,
                    rawArtist: rawTitle,
                    tags: normaliser.normalise(title: track.artist, artist: track.title)
                )
                : nil
            let extrasRaw = criteria.extraFields.map { TextFolding.collapseWhitespace($0.field.value(in: track)) }
            return PreparedTrack(
                index: index,
                track: track,
                normal: normal,
                swapped: swapped,
                album: normaliser.fold(track.album),
                extrasRaw: extrasRaw,
                extrasFolded: extrasRaw.map(normaliser.fold)
            )
        }
    }

    // MARK: - Blocking

    enum Blocking {
        case exactTitle(identical: Bool)
        case exactArtist(identical: Bool, subset: Bool)
        case titleTokens
        case artistTokens

        /// Picks the strictest field to block on. Returns nil when neither
        /// title nor artist is compared, since there's nothing to match on.
        init?(criteria: MatchCriteria) {
            if criteria.title.level.isExact {
                self = .exactTitle(identical: criteria.title.level == .identical)
            } else if criteria.artist.level.isExact {
                self = .exactArtist(identical: criteria.artist.level == .identical, subset: criteria.artistSubsetMatches)
            } else if criteria.title.level != .ignore {
                self = .titleTokens
            } else if criteria.artist.level != .ignore {
                self = .artistTokens
            } else {
                return nil
            }
        }

        func keys(_ v: FieldView) -> [String] {
            switch self {
            case .exactTitle(let identical):
                let key = identical ? v.rawTitle : v.tags.title
                return key.isEmpty ? [] : [key]
            case .exactArtist(let identical, let subset):
                if identical { return [v.rawArtist] }
                if subset, !v.tags.primaryArtists.isEmpty { return v.tags.primaryArtists }
                return [v.tags.artist]
            case .titleTokens:
                return Self.tokens(v.tags.title)
            case .artistTokens:
                return Self.tokens(v.tags.artist)
            }
        }

        /// Used to split oversized buckets: the first letters of the other field.
        func secondaryKey(_ v: FieldView) -> String {
            switch self {
            case .exactTitle, .titleTokens: String(v.tags.artist.prefix(3))
            case .exactArtist, .artistTokens: String(v.tags.title.prefix(3))
            }
        }

        static func tokens(_ s: String) -> [String] {
            Array(Set(TextFolding.stripPunctuation(s.lowercased()).split(separator: " ").map(String.init)))
        }
    }

    /// Buckets of track indices, each with at least two members.
    func makeBuckets(_ prepared: [PreparedTrack], blocking: Blocking) -> [[Int]] {
        var byKey: [String: [Int]] = [:]
        for p in prepared {
            var keys = Set(blocking.keys(p.normal))
            if let swapped = p.swapped { keys.formUnion(blocking.keys(swapped)) }
            for key in keys { byKey[key, default: []].append(p.index) }
        }

        var buckets: [[Int]] = []
        for members in byKey.values where members.count >= 2 {
            if members.count <= maxBucketSize {
                buckets.append(members)
                continue
            }
            var split: [String: [Int]] = [:]
            for i in members {
                var keys: Set<String> = [blocking.secondaryKey(prepared[i].normal)]
                if let swapped = prepared[i].swapped { keys.insert(blocking.secondaryKey(swapped)) }
                for key in keys { split[key, default: []].append(i) }
            }
            buckets += split.values.filter { $0.count >= 2 }
        }
        // Deterministic order, largest first so parallel chunks balance.
        return buckets
            .map { $0.sorted() }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0[0] < $1[0] }
    }

    // MARK: - Compare

    struct Edge: Sendable {
        let a: Int
        let b: Int
        let score: Double
        let reasons: Set<MatchReason>
    }

    func compare(buckets: [[Int]], prepared: [PreparedTrack], progress: ProgressHandler?) async throws -> [Edge] {
        guard !buckets.isEmpty else { return [] }

        // Each track's bucket IDs, ascending, so a pair is compared only in
        // the first bucket the two tracks share.
        var bucketsOfTrack = [[Int]](repeating: [], count: prepared.count)
        for (id, bucket) in buckets.enumerated() {
            for i in bucket { bucketsOfTrack[i].append(id) }
        }

        let chunkCount = min(buckets.count, max(1, ProcessInfo.processInfo.activeProcessorCount * 4))
        let criteria = self.criteria
        let membership = bucketsOfTrack

        return try await withThrowingTaskGroup(of: [Edge].self) { group in
            for chunk in 0..<chunkCount {
                group.addTask {
                    var edges: [Edge] = []
                    var comparisons = 0
                    for id in stride(from: chunk, to: buckets.count, by: chunkCount) {
                        let bucket = buckets[id]
                        for x in 0..<bucket.count {
                            for y in (x + 1)..<bucket.count {
                                let i = bucket[x], j = bucket[y]
                                guard Self.firstSharedBucket(membership[i], membership[j]) == id else { continue }
                                comparisons += 1
                                if comparisons % 4096 == 0 { try Task.checkCancellation() }
                                if let edge = Self.compare(prepared[i], prepared[j], criteria: criteria) {
                                    edges.append(edge)
                                }
                            }
                        }
                    }
                    return edges
                }
            }

            var all: [Edge] = []
            var finished = 0
            for try await edges in group {
                all += edges
                finished += 1
                progress?(Double(finished) / Double(chunkCount))
            }
            return all
        }
    }

    static func firstSharedBucket(_ a: [Int], _ b: [Int]) -> Int? {
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] { return a[i] }
            if a[i] < b[j] { i += 1 } else { j += 1 }
        }
        return nil
    }

    static func compare(_ a: PreparedTrack, _ b: PreparedTrack, criteria: MatchCriteria) -> Edge? {
        guard let constraints = checkConstraints(a, b, criteria: criteria) else { return nil }

        var best = compareViews(a.normal, b.normal, criteria: criteria)
        if let swapped = b.swapped, var alt = compareViews(a.normal, swapped, criteria: criteria) {
            alt.reasons.insert(.swappedTitleAndArtist)
            if best == nil || alt.score > best!.score { best = alt }
        }
        guard var fields = best else { return nil }

        fields.add(constraints)
        return Edge(a: a.index, b: b.index, score: fields.score, reasons: fields.reasons)
    }

    struct Tally {
        var weighted = 0.0
        var weights = 0.0
        var reasons: Set<MatchReason> = []

        var score: Double { weights > 0 ? weighted / weights : 1 }

        mutating func add(_ score: Double, weight: Double, reason: MatchReason) {
            weighted += score * weight
            weights += weight
            reasons.insert(reason)
        }

        mutating func add(_ other: Tally) {
            weighted += other.weighted
            weights += other.weights
            reasons.formUnion(other.reasons)
        }
    }

    enum FieldOutcome {
        case ignored, fail
        case pass(Double, MatchReason)
    }

    /// Duration, track number, album, format and extra fields: everything
    /// that doesn't depend on title/artist orientation.
    static func checkConstraints(_ a: PreparedTrack, _ b: PreparedTrack, criteria: MatchCriteria) -> Tally? {
        var tally = Tally()

        if let tolerance = criteria.durationTolerance, let da = a.track.duration, let db = b.track.duration {
            let diff = abs(da - db)
            guard diff <= tolerance else { return nil }
            let score = tolerance > 0 ? 1 - 0.5 * diff / tolerance : 1
            tally.add(score, weight: 0.15, reason: .durationWithinTolerance)
        }
        guard criteria.trackNumber.accepts(a.track.trackNumber, b.track.trackNumber),
              criteria.album.accepts(a.album, b.album),
              criteria.format.accepts(a.track.audio.format, b.track.audio.format)
        else { return nil }

        for (n, extra) in criteria.extraFields.enumerated() {
            let outcome = compareText(
                extra.rule,
                raw: (a.extrasRaw[n], b.extrasRaw[n]),
                normalised: (a.extrasFolded[n], b.extrasFolded[n]),
                allowEmpty: true,
                reasons: [.extraFieldsMatched, .extraFieldsMatched, .extraFieldsMatched, .extraFieldsMatched]
            )
            switch outcome {
            case .fail: return nil
            case .ignored: break
            case .pass(let score, let reason): tally.add(score, weight: 0.1, reason: reason)
            }
        }
        return tally
    }

    static func compareViews(_ a: FieldView, _ b: FieldView, criteria: MatchCriteria) -> Tally? {
        var tally = Tally()

        let title = compareText(
            criteria.title,
            raw: (a.rawTitle, b.rawTitle),
            normalised: (a.tags.title, b.tags.title),
            allowEmpty: false,
            reasons: [.identicalTitle, .sameTitle, .similarTitle, .fuzzyTitle]
        )
        switch title {
        case .fail: return nil
        case .ignored: break
        case .pass(let score, let reason):
            tally.add(score, weight: 0.5, reason: reason)
            if criteria.title.level != .identical,
               !a.tags.removedFromTitle.isEmpty || !b.tags.removedFromTitle.isEmpty {
                tally.reasons.insert(.versionTextIgnored)
            }
        }

        switch compareArtists(a, b, criteria: criteria) {
        case .fail: return nil
        case .ignored: break
        case .pass(let score, let reason):
            tally.add(score, weight: 0.35, reason: reason)
            if criteria.artist.level != .identical,
               criteria.normalisation.separateFeaturedArtists,
               !a.tags.featuredArtists.isEmpty || !b.tags.featuredArtists.isEmpty,
               a.tags.featuredArtists != b.tags.featuredArtists {
                tally.reasons.insert(.featuredArtistIgnored)
            }
        }
        return tally
    }

    /// `reasons` holds the reason for identical, same, similar and fuzzy, in that order.
    static func compareText(
        _ rule: FieldRule,
        raw: (String, String),
        normalised: (String, String),
        allowEmpty: Bool,
        reasons: [MatchReason]
    ) -> FieldOutcome {
        switch rule.level {
        case .ignore:
            return .ignored
        case .identical:
            guard raw.0 == raw.1, allowEmpty || !raw.0.isEmpty else { return .fail }
            return .pass(1, reasons[0])
        case .same, .similar, .fuzzy:
            let (a, b) = normalised
            if a.isEmpty || b.isEmpty {
                return allowEmpty && a == b ? .pass(1, reasons[1]) : .fail
            }
            if a == b { return .pass(1, reasons[1]) }
            switch rule.level {
            case .similar:
                let s = Similarity.similar(a, b)
                return s >= rule.threshold ? .pass(s, reasons[2]) : .fail
            case .fuzzy:
                let s = Similarity.fuzzy(a, b)
                return s >= rule.threshold ? .pass(s, reasons[3]) : .fail
            default:
                return .fail
            }
        }
    }

    static func compareArtists(_ a: FieldView, _ b: FieldView, criteria: MatchCriteria) -> FieldOutcome {
        let rule = criteria.artist
        if rule.level == .ignore || rule.level == .identical {
            return compareText(
                rule,
                raw: (a.rawArtist, b.rawArtist),
                normalised: (a.tags.artist, b.tags.artist),
                allowEmpty: true,
                reasons: [.identicalArtist, .sameArtist, .similarArtist, .fuzzyArtist]
            )
        }
        let setA = a.tags.primaryArtists, setB = b.tags.primaryArtists
        if setA == setB { return .pass(1, .sameArtist) }
        if criteria.artistSubsetMatches, !setA.isEmpty, !setB.isEmpty {
            let x = Set(setA), y = Set(setB)
            if x.isSubset(of: y) || y.isSubset(of: x) { return .pass(0.9, .artistSubset) }
        }
        return compareText(
            rule,
            raw: (a.rawArtist, b.rawArtist),
            normalised: (a.tags.artist, b.tags.artist),
            allowEmpty: true,
            reasons: [.identicalArtist, .sameArtist, .similarArtist, .fuzzyArtist]
        )
    }

    // MARK: - Group

    func group(edges: [Edge], prepared: [PreparedTrack]) -> [DuplicateGroup] {
        var unionFind = UnionFind(count: prepared.count)
        var adjacency: [Int: [Int: Edge]] = [:]
        for edge in edges {
            unionFind.union(edge.a, edge.b)
            adjacency[edge.a, default: [:]][edge.b] = edge
            adjacency[edge.b, default: [:]][edge.a] = edge
        }

        var memberLists: [[Int]] = []
        for component in unionFind.components() {
            if criteria.requireAnchorMatch {
                memberLists += Self.anchoredSubgroups(component, adjacency: adjacency)
            } else {
                let anchor = component.max { lhs, rhs in
                    let dl = adjacency[lhs]?.count ?? 0, dr = adjacency[rhs]?.count ?? 0
                    return dl != dr ? dl < dr : lhs > rhs
                }!
                memberLists.append([anchor] + component.filter { $0 != anchor })
            }
        }

        let groups = memberLists.map { members -> DuplicateGroup in
            var total = 0.0, count = 0
            var reasons: Set<MatchReason> = []
            for (n, i) in members.enumerated() {
                for j in members[(n + 1)...] {
                    guard let edge = adjacency[i]?[j] else { continue }
                    total += edge.score
                    count += 1
                    reasons.formUnion(edge.reasons)
                }
            }
            return DuplicateGroup(
                id: 0,
                trackIDs: members.map { prepared[$0].track.id },
                confidence: count > 0 ? total / Double(count) : 0,
                reasons: reasons.sorted()
            )
        }

        let anchors = memberLists.map { prepared[$0[0]].normal.tags }
        return zip(groups, anchors)
            .sorted { lhs, rhs in
                let (a, b) = (lhs.1, rhs.1)
                if a.artist != b.artist { return a.artist < b.artist }
                if a.title != b.title { return a.title < b.title }
                return lhs.0.trackIDs[0] < rhs.0.trackIDs[0]
            }
            .enumerated()
            .map { n, pair in
                var g = pair.0
                g.id = n
                return g
            }
    }

    /// Splits a component so that every member matches its group's anchor.
    /// The anchor is the member with the most matches (lowest index on ties).
    static func anchoredSubgroups(_ component: [Int], adjacency: [Int: [Int: Edge]]) -> [[Int]] {
        var remaining = Set(component)
        var result: [[Int]] = []
        func degree(_ i: Int) -> Int {
            adjacency[i]?.keys.filter(remaining.contains).count ?? 0
        }
        while remaining.count >= 2 {
            let anchor = remaining.max { lhs, rhs in
                let dl = degree(lhs), dr = degree(rhs)
                return dl != dr ? dl < dr : lhs > rhs
            }!
            let neighbours = (adjacency[anchor]?.keys.filter(remaining.contains) ?? []).sorted()
            remaining.remove(anchor)
            guard !neighbours.isEmpty else { continue }
            result.append([anchor] + neighbours)
            remaining.subtract(neighbours)
        }
        return result
    }
}
