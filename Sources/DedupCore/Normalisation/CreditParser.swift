/// Parses featured-artist credits and collaborations out of tag text.
public enum CreditParser {
    static let featMarkers: Set<String> = ["feat", "feat.", "ft", "ft.", "featuring", "feat:", "ft:", "featuring:"]

    /// Word separators between collaborating artists. `x` and `and` are only
    /// separators when they stand alone with names on both sides.
    static let collabSeparators: Set<String> = [
        "&", "and", "x", "×", "vs", "vs.", "versus", "+", "/", ",", ";", "with",
    ]

    /// Splits a featured-artist credit off a title or artist string.
    ///
    ///     "A ft. B"                    → ("A", "B")
    ///     "Song (feat. B) (Extended)"  → ("Song (Extended)", "B")
    ///     "Song feat. B [Radio Edit]"  → ("Song [Radio Edit]", "B")
    ///
    /// A marker as the first word is ignored, so a name like "Ft Worth" survives.
    public static func splitFeatured(_ s: String) -> (main: String, featured: String?) {
        let words = TextFolding.collapseWhitespace(s).split(separator: " ").map(String.init)
        for (i, word) in words.enumerated() where i > 0 {
            var core = word.lowercased()
            var opener: Character?
            if let first = core.first, Brackets.pairs[first] != nil {
                opener = first
                core.removeFirst()
            }
            guard featMarkers.contains(core) else { continue }

            let before = words[..<i].joined(separator: " ")
            let after = words[(i + 1)...].joined(separator: " ")
            let featured: String
            let remainder: String
            if let opener, let closer = Brackets.pairs[opener] {
                (featured, remainder) = cutAtCloser(after, closer: closer)
            } else {
                (featured, remainder) = cutBeforeOpener(after)
            }
            let main = TextFolding.collapseWhitespace(before + " " + remainder)
            let feat = TextFolding.collapseWhitespace(featured)
            return (main, feat.isEmpty ? nil : feat)
        }
        return (TextFolding.collapseWhitespace(s), nil)
    }

    /// `"B) (Extended)"` → `("B", "(Extended)")`
    private static func cutAtCloser(_ s: String, closer: Character) -> (String, String) {
        guard let idx = s.firstIndex(of: closer) else { return (s, "") }
        return (String(s[..<idx]), String(s[s.index(after: idx)...]))
    }

    /// `"B [Radio Edit]"` → `("B", "[Radio Edit]")`
    private static func cutBeforeOpener(_ s: String) -> (String, String) {
        guard let idx = s.firstIndex(where: { Brackets.pairs[$0] != nil }) else { return (s, "") }
        return (String(s[..<idx]), String(s[idx...]))
    }

    /// Splits a credit into individual artists on `&`, `and`, `x`, `vs`, `,`
    /// and similar separators. Empty names are dropped.
    ///
    ///     "A & B, C"  → ["A", "B", "C"]
    ///     "A vs. B"   → ["A", "B"]
    public static func splitCollaborators(_ s: String) -> [String] {
        var padded = ""
        for c in s {
            if c == "," || c == ";" {
                padded += " \(c) "
            } else {
                padded.append(c)
            }
        }
        var groups: [[Substring]] = [[]]
        var lastSeparator: Substring?
        for word in padded.split(whereSeparator: \.isWhitespace) {
            if collabSeparators.contains(word.lowercased()) {
                if !groups[groups.count - 1].isEmpty {
                    groups.append([])
                    lastSeparator = word
                    continue
                }
                if groups.count > 1 { continue } // consecutive separators
            }
            groups[groups.count - 1].append(word)
        }
        if groups.count > 1, groups[groups.count - 1].isEmpty {
            groups.removeLast()
            // A trailing word separator is part of the name: "Malcolm X".
            if let sep = lastSeparator, sep.allSatisfy(\.isLetter) {
                groups[groups.count - 1].append(sep)
            }
        }
        let names = groups.map { $0.joined(separator: " ") }
        return names.filter { !$0.isEmpty }
    }

    /// Removes a leading track number that was left in a title.
    ///
    ///     "01 - Song", "01. Song", "1) Song", "01_Song", "1-01 Song", "01 Song" → "Song"
    ///     "99 Luftballons", "1999", "7 Seconds"                              → unchanged
    ///
    /// A bare space after the number only counts when the number has a
    /// leading zero or is a disc-track pair such as `1-01`.
    public static func removingTrackNumberPrefix(_ s: String) -> String {
        let chars = Array(s)
        var i = 0

        func digitRun() -> Int {
            let start = i
            while i < chars.count, chars[i].isASCII, chars[i].isNumber, i - start < 3 { i += 1 }
            return i - start
        }

        let firstRun = digitRun()
        guard firstRun > 0 else { return s }
        let leadingZero = chars[0] == "0" && firstRun > 1
        var isDiscTrack = false

        if i + 1 < chars.count, chars[i] == "-" || chars[i] == ".", chars[i + 1].isASCII, chars[i + 1].isNumber {
            let save = i
            i += 1
            if digitRun() >= 2 {
                isDiscTrack = true
            } else {
                i = save
            }
        }
        if i < chars.count, chars[i].isNumber { return s }

        var sawSpace = false
        while i < chars.count, chars[i] == " " { i += 1; sawSpace = true }

        var sawSeparator = false
        if i < chars.count, [".", "-", ")", "_", "–", "—"].contains(chars[i]) {
            let isDash = chars[i] == "-" || chars[i] == "–" || chars[i] == "—"
            i += 1
            var spaceAfter = false
            while i < chars.count, chars[i] == " " { i += 1; spaceAfter = true }
            // "2-4-6-8 Motorway" is a title, "01 - Song" and "01 -Song" are not.
            sawSeparator = !isDash || sawSpace || spaceAfter
        }
        guard sawSeparator || (sawSpace && (leadingZero || isDiscTrack)) else { return s }
        guard i < chars.count, !chars[i].isNumber else { return s }

        let rest = String(chars[i...])
        guard rest.contains(where: \.isLetter) else { return s }
        return rest
    }
}
