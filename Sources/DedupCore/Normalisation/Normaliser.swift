/// The comparable form of a track's title and artist.
public struct NormalisedTags: Sendable, Hashable {
    public var title: String
    /// Sorted, de-duplicated primary artists.
    public var primaryArtists: [String]
    /// Sorted, de-duplicated featured artists (from the artist or title tag).
    public var featuredArtists: [String]
    /// Text removed from the title (for example "Original Mix" or "01"),
    /// kept so the UI can explain a match.
    public var removedFromTitle: [String]

    public init(title: String, primaryArtists: [String], featuredArtists: [String] = [], removedFromTitle: [String] = []) {
        self.title = title
        self.primaryArtists = primaryArtists
        self.featuredArtists = featuredArtists
        self.removedFromTitle = removedFromTitle
    }

    /// Primary artists joined into one comparable string.
    public var artist: String { primaryArtists.joined(separator: " & ") }
}

/// Applies `NormalisationOptions` to a title and artist.
public struct Normaliser: Sendable {
    public var options: NormalisationOptions

    public init(options: NormalisationOptions = .minimal) {
        self.options = options
    }

    public func normalise(_ track: Track) -> NormalisedTags {
        normalise(title: track.title, artist: track.artist, fileStem: track.fileStem)
    }

    public func normalise(title rawTitle: String, artist rawArtist: String, fileStem: String? = nil) -> NormalisedTags {
        var title = TextFolding.collapseWhitespace(rawTitle)
        var artist = TextFolding.collapseWhitespace(rawArtist)
        var removed: [String] = []
        var featured: [String] = []

        if options.filenameFallback, title.isEmpty, let fileStem {
            (title, artist) = Self.parseFileStem(fileStem, artist: artist)
        }
        if options.splitArtistFromTitle {
            (title, artist) = splitArtist(fromTitle: title, artist: artist)
        }
        if options.stripTrackNumberPrefix {
            let stripped = CreditParser.removingTrackNumberPrefix(title)
            if stripped != title {
                removed.append(String(title.dropLast(stripped.count)).trimmingSeparators())
                title = stripped
            }
        }
        if options.stripFeaturedFromTitle {
            let (main, feat) = CreditParser.splitFeatured(title)
            if let feat, !main.isEmpty {
                title = main
                featured += splitNames(feat)
                removed.append("feat. \(feat)")
            }
        }
        (title, removed) = stripVersions(from: title, removed: removed)

        let primary: [String]
        if options.separateFeaturedArtists {
            let (main, feat) = CreditParser.splitFeatured(artist)
            primary = splitNames(main)
            if let feat { featured += splitNames(feat) }
        } else {
            primary = splitNames(artist)
        }

        return NormalisedTags(
            title: fold(title),
            primaryArtists: Self.uniqueSorted(primary.map(foldArtist)),
            featuredArtists: Self.uniqueSorted(featured.map(foldArtist)),
            removedFromTitle: removed
        )
    }

    // MARK: - Steps

    private func splitNames(_ s: String) -> [String] {
        options.splitCollaborations ? CreditParser.splitCollaborators(s) : [s]
    }

    private func foldArtist(_ name: String) -> String {
        fold(options.ignoreLeadingThe ? TextFolding.removingLeadingThe(name) : name)
    }

    /// `Artist - Song` in the title, where the artist tag is empty or matches.
    private func splitArtist(fromTitle title: String, artist: String) -> (String, String) {
        let parts = TextFolding.splitOnSpacedDash(title)
        guard parts.count >= 2, let head = parts.first, !head.isEmpty else { return (title, artist) }
        let rest = parts.dropFirst().joined(separator: " - ")
        if artist.isEmpty {
            return (rest, head)
        }
        if fold(head) == fold(artist) {
            return (rest, artist)
        }
        return (title, artist)
    }

    private func stripVersions(from title: String, removed: [String]) -> (String, [String]) {
        var removed = removed
        let originalCount = removed.count
        var result = title

        if options.stripAllBrackets || options.versionStripping != .off {
            let segments = Brackets.topLevelSegments(in: result)
            let toRemove = segments.filter { options.stripAllBrackets || shouldStrip(VersionClassifier.classify($0.inner)) }
            let candidate = Brackets.removing(toRemove.map(\.range), from: result)
            if !candidate.trimmingSeparators().isEmpty {
                removed += toRemove.map { String($0.inner) }
                result = candidate
            }
        }

        if options.versionStripping != .off {
            var parts = TextFolding.splitOnSpacedDash(result)
            while parts.count >= 2, let last = parts.last, shouldStrip(VersionClassifier.classify(last)) {
                removed.append(last)
                parts.removeLast()
            }
            result = parts.joined(separator: " - ")
        }
        if removed.count > originalCount {
            result = result.trimmingSeparators()
        }
        return (result, removed)
    }

    private func shouldStrip(_ kind: VersionKind) -> Bool {
        switch (options.versionStripping, kind) {
        case (.neutralOnly, .neutral), (.allVersions, .neutral), (.allVersions, .distinct): true
        default: false
        }
    }

    /// Case, diacritic, punctuation and whitespace folding.
    public func fold(_ s: String) -> String {
        var s = s
        if options.unifyPunctuation || options.ignorePunctuation { s = TextFolding.unifyPunctuation(s) }
        if options.foldDiacritics { s = TextFolding.foldDiacritics(s) }
        if options.ignoreCase { s = s.lowercased() }
        if options.ampersandAsAnd { s = TextFolding.ampersandToAnd(s) }
        if options.ignorePunctuation { s = TextFolding.stripPunctuation(s) }
        s = TextFolding.collapseWhitespace(s)
        if options.ignoreSpaces { s.removeAll(where: \.isWhitespace) }
        return s
    }

    // MARK: - Helpers

    /// `01 - Artist - Title` → ("Title", "Artist"). Keeps an existing artist tag.
    static func parseFileStem(_ stem: String, artist: String) -> (title: String, artist: String) {
        let cleaned = CreditParser.removingTrackNumberPrefix(TextFolding.collapseWhitespace(stem))
        let parts = TextFolding.splitOnSpacedDash(cleaned)
        guard parts.count >= 2 else { return (cleaned, artist) }
        let title = parts.dropFirst().joined(separator: " - ")
        return (title, artist.isEmpty ? parts[0] : artist)
    }

    static func uniqueSorted(_ names: [String]) -> [String] {
        Array(Set(names.filter { !$0.isEmpty })).sorted()
    }
}

extension String {
    /// Trims whitespace and dangling separators such as a trailing ` -`.
    func trimmingSeparators() -> String {
        var s = Substring(self)
        let junk: Set<Character> = [" ", "-", "–", "—", "_", ".", ":", "|", "/"]
        while let f = s.first, junk.contains(f) || f.isWhitespace { s.removeFirst() }
        while let l = s.last, junk.contains(l) || l.isWhitespace { s.removeLast() }
        return String(s)
    }
}
