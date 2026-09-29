import Foundation

/// Low-level string transforms used by the normalisation pipeline.
public enum TextFolding {
    static let dashes: Set<Character> = ["-", "‐", "‑", "‒", "–", "—", "―", "−"]
    static let singleQuotes: Set<Character> = ["‘", "’", "‚", "‛", "′", "`", "´"]
    static let doubleQuotes: Set<Character> = ["“", "”", "„", "‟", "″", "«", "»"]

    /// Letters that Unicode decomposition does not reduce to ASCII.
    static let specialLetters: [Character: String] = [
        "ß": "ss", "ø": "o", "Ø": "O", "æ": "ae", "Æ": "AE", "œ": "oe", "Œ": "OE",
        "ł": "l", "Ł": "L", "đ": "d", "Đ": "D", "þ": "th", "Þ": "Th", "ı": "i",
    ]

    /// Trims and collapses runs of whitespace (including non-breaking spaces) to single spaces.
    public static func collapseWhitespace(_ s: some StringProtocol) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Maps typographic dashes and quotes to their ASCII forms.
    public static func unifyPunctuation(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for c in s {
            if dashes.contains(c) {
                out.append("-")
            } else if singleQuotes.contains(c) {
                out.append("'")
            } else if doubleQuotes.contains(c) {
                out.append("\"")
            } else {
                out.append(c)
            }
        }
        return out
    }

    /// `Café Björk Ørsted` → `Cafe Bjork Orsted`.
    public static func foldDiacritics(_ s: String) -> String {
        var mapped = ""
        mapped.reserveCapacity(s.utf8.count)
        for c in s {
            if let replacement = specialLetters[c] {
                mapped += replacement
            } else {
                mapped.append(c)
            }
        }
        return mapped.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Replaces a standalone `&` or `+` with `and`.
    public static func ampersandToAnd(_ s: String) -> String {
        collapseWhitespace(s)
            .split(separator: " ")
            .map { $0 == "&" || $0 == "+" ? "and" : String($0) }
            .joined(separator: " ")
    }

    /// Removes punctuation and symbols. Apostrophes and full stops are
    /// deleted (`Don't` → `Dont`, `Mr.` → `Mr`); everything else that isn't
    /// a letter or digit becomes a space. The result is whitespace-collapsed.
    public static func stripPunctuation(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for c in s {
            if c.isLetter || c.isNumber {
                out.append(c)
            } else if c == "'" || c == "." || singleQuotes.contains(c) {
                continue
            } else {
                out.append(" ")
            }
        }
        return collapseWhitespace(out)
    }

    /// `The Prodigy` → `Prodigy`, `Prodigy, The` → `Prodigy`.
    /// A name that is only "The" is left alone.
    public static func removingLeadingThe(_ s: String) -> String {
        let trimmed = collapseWhitespace(s)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("the "), trimmed.count > 4 {
            return String(trimmed.dropFirst(4))
        }
        if lower.hasSuffix(", the"), trimmed.count > 5 {
            return String(trimmed.dropLast(5))
        }
        return trimmed
    }

    /// Splits on a dash surrounded by spaces (`A - B`, `A – B`, `A — B`).
    /// Hyphens inside words (`Hip-Hop`) are not separators.
    public static func splitOnSpacedDash(_ s: String) -> [String] {
        let chars = Array(s)
        var parts: [String] = []
        var current = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if dashes.contains(c),
               i > 0, chars[i - 1].isWhitespace,
               i + 1 < chars.count, chars[i + 1].isWhitespace {
                parts.append(current)
                current = ""
            } else {
                current.append(c)
            }
            i += 1
        }
        parts.append(current)
        return parts.map { collapseWhitespace($0) }
    }
}
