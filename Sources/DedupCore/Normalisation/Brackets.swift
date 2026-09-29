/// Finds top-level bracketed segments: `(...)`, `[...]` and `{...}`.
enum Brackets {
    static let pairs: [Character: Character] = ["(": ")", "[": "]", "{": "}"]

    struct Segment {
        /// Range of the whole segment, including the brackets.
        let range: Range<String.Index>
        /// Text between the brackets.
        let inner: Substring
    }

    /// Nested brackets belong to their outermost segment. Unbalanced or
    /// mismatched brackets are ignored.
    static func topLevelSegments(in s: String) -> [Segment] {
        var result: [Segment] = []
        var stack: [(open: Character, index: String.Index)] = []
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if pairs[c] != nil {
                stack.append((c, i))
            } else if let top = stack.last, pairs[top.open] == c {
                stack.removeLast()
                if stack.isEmpty {
                    let end = s.index(after: i)
                    result.append(Segment(range: top.index..<end, inner: s[s.index(after: top.index)..<i]))
                }
            }
            i = s.index(after: i)
        }
        return result
    }

    /// Returns `s` without the given ranges, whitespace-collapsed.
    static func removing(_ ranges: [Range<String.Index>], from s: String) -> String {
        guard !ranges.isEmpty else { return s }
        var out = ""
        var cursor = s.startIndex
        for r in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) where r.lowerBound >= cursor {
            out += s[cursor..<r.lowerBound]
            out += " "
            cursor = r.upperBound
        }
        out += s[cursor...]
        return TextFolding.collapseWhitespace(out)
    }
}
