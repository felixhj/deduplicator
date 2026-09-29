/// How much version text ("Original Mix", "Carl Craig Remix") to strip from titles.
public enum VersionStripping: String, Sendable, Hashable, Codable, CaseIterable {
    /// Keep all version text.
    case off
    /// Strip neutral labels such as "Original Mix", "Radio Edit" and "Remastered".
    case neutralOnly
    /// Also strip distinct versions such as "X Remix", "Dub" and "Live", so
    /// every version of a track is grouped together.
    case allVersions
}

/// Every toggleable normalisation rule. Stripping rules default to off.
public struct NormalisationOptions: Sendable, Hashable, Codable {
    // MARK: Folding (both fields)

    /// `SONG` = `song`
    public var ignoreCase = true
    /// `Café` = `Cafe`
    public var foldDiacritics = false
    /// `–`/`—` → `-`, curly quotes → straight
    public var unifyPunctuation = false
    /// Remove all punctuation: `Mr. Oizo` = `Mr Oizo`, `Don't` = `Dont`
    public var ignorePunctuation = false
    /// `&` and `+` → `and`
    public var ampersandAsAnd = false
    /// `Energy52` = `Energy 52`
    public var ignoreSpaces = false

    // MARK: Title rules

    /// Bracketed and ` - ` suffixed version text.
    public var versionStripping: VersionStripping = .off
    /// Remove every bracketed segment, whatever it says.
    public var stripAllBrackets = false
    /// `Song (feat. X)` → `Song`
    public var stripFeaturedFromTitle = false
    /// `01 - Song` → `Song`
    public var stripTrackNumberPrefix = false
    /// Title `Artist - Song` with the artist tag empty or equal to `Artist` → `Song`
    public var splitArtistFromTitle = false
    /// With no title tag, read `Artist - Title` from the filename.
    public var filenameFallback = false

    // MARK: Artist rules

    /// `A ft. B` → primary `A`, featured `B`. Featured artists are then
    /// ignored when comparing.
    public var separateFeaturedArtists = false
    /// `A & B`, `A x B`, `A vs. B`, `A, B` → the set {A, B}, so order doesn't matter.
    public var splitCollaborations = false
    /// `The Prodigy` = `Prodigy`
    public var ignoreLeadingThe = false

    public init() {}
}

// MARK: - Presets

public extension NormalisationOptions {
    /// Case-insensitive only. This is the default.
    static let minimal = NormalisationOptions()

    /// Folding only. Doesn't strip any text.
    static var tidy: NormalisationOptions {
        var o = NormalisationOptions()
        o.foldDiacritics = true
        o.unifyPunctuation = true
        o.ampersandAsAnd = true
        return o
    }

    /// Sensible for DJ and electronic libraries: strips neutral mix labels and
    /// featured credits but keeps remixes apart.
    static var djLibrary: NormalisationOptions {
        var o = tidy
        o.versionStripping = .neutralOnly
        o.stripFeaturedFromTitle = true
        o.stripTrackNumberPrefix = true
        o.splitArtistFromTitle = true
        o.separateFeaturedArtists = true
        o.splitCollaborations = true
        o.ignoreLeadingThe = true
        return o
    }

    /// Groups every version of a song together and ignores punctuation.
    static var aggressive: NormalisationOptions {
        var o = djLibrary
        o.versionStripping = .allVersions
        o.ignorePunctuation = true
        o.filenameFallback = true
        return o
    }
}
