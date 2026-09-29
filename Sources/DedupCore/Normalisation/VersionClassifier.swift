/// What a bracketed or dash-suffixed title fragment says about the recording.
public enum VersionKind: String, Sendable, Hashable, Codable {
    /// Same recording, different label: "Original Mix", "Radio Edit", "2011 Remaster".
    case neutral
    /// A different recording: "Carl Craig Remix", "Dub", "Live at Wembley", "Club Mix".
    case distinct
    /// Not version text at all: "Part 2", "Interlude", "Love Theme".
    case notAVersion
}

public enum VersionClassifier {
    /// Any of these words means a different recording.
    static let distinctWords: Set<String> = [
        "remix", "remixes", "rmx", "remixed", "dub", "vip", "rework", "reworked",
        "bootleg", "live", "acoustic", "instrumental", "acapella", "acappella",
        "cappella", "reprise", "demo", "flip", "refix", "reedit", "mashup",
        "karaoke", "unplugged", "cover", "orchestral", "sped", "slowed", "reverb",
        "nightcore", "megamix", "medley", "rerub", "remode", "redux",
    ]

    /// Words that only describe edition, length or mastering.
    static let neutralWords: Set<String> = [
        "original", "extended", "radio", "single", "album", "lp", "ep", "edit",
        "version", "mix", "mixed", "remaster", "remastered", "remasters", "mastered",
        "digitally", "digital", "explicit", "clean", "dirty", "censored", "uncensored",
        "mono", "stereo", "main", "full", "length", "short", "long", "12", "7",
        "inch", "12inch", "7inch", "vinyl", "cd", "bonus", "track", "deluxe",
        "edition", "hq", "hd", "official", "audio", "the", "a",
    ]

    /// Words that name a mix or edit. When they appear alongside
    /// non-neutral words ("Club Mix", "Joe Smith Edit") the fragment is a
    /// distinct version.
    static let versionMarkers: Set<String> = [
        "mix", "edit", "version", "remaster", "remastered",
    ]

    static let fillerWords: Set<String> = ["the", "a"]

    public static func classify(_ fragment: some StringProtocol) -> VersionKind {
        let tokens = tokenise(String(fragment))
        guard !tokens.isEmpty else { return .notAVersion }

        if tokens.contains(where: distinctWords.contains) {
            return .distinct
        }
        let allNeutral = tokens.allSatisfy { neutralWords.contains($0) || isYear($0) }
        if allNeutral, tokens.contains(where: { !fillerWords.contains($0) }) {
            return .neutral
        }
        if tokens.contains(where: versionMarkers.contains) {
            return .distinct
        }
        return .notAVersion
    }

    /// Lowercases and folds, deletes hyphens, apostrophes and full stops
    /// (so "Re-Edit" → "reedit"), and splits on everything else.
    static func tokenise(_ s: String) -> [String] {
        let folded = TextFolding.foldDiacritics(TextFolding.unifyPunctuation(s)).lowercased()
        var cleaned = ""
        for c in folded {
            if c.isLetter || c.isNumber {
                cleaned.append(c)
            } else if c == "-" || c == "'" || c == "." {
                continue
            } else {
                cleaned.append(" ")
            }
        }
        return cleaned.split(separator: " ").map(String.init)
    }

    static func isYear(_ token: String) -> Bool {
        guard token.count == 4, let n = Int(token) else { return false }
        return (1900...2099).contains(n)
    }
}
