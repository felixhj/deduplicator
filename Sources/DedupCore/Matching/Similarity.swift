/// String similarity metrics. Every ratio is in 0...1, where 1 means identical.
public enum Similarity {
    public static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        levenshteinDistance(Array(a.unicodeScalars), Array(b.unicodeScalars))
    }

    static func levenshteinDistance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// 1 − edit distance ÷ length of the longer string. Conservative: good for typos.
    public static func levenshteinRatio(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let x = Array(a.unicodeScalars)
        let y = Array(b.unicodeScalars)
        let longest = max(x.count, y.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(levenshteinDistance(x, y)) / Double(longest)
    }

    /// Jaro-Winkler similarity. Rewards a shared prefix, which suits titles
    /// whose endings vary.
    public static func jaroWinkler(_ a: String, _ b: String, prefixScale: Double = 0.1) -> Double {
        if a == b { return 1 }
        let s1 = Array(a.unicodeScalars)
        let s2 = Array(b.unicodeScalars)
        if s1.isEmpty || s2.isEmpty { return 0 }

        let window = max(0, max(s1.count, s2.count) / 2 - 1)
        var s1Matched = [Bool](repeating: false, count: s1.count)
        var s2Matched = [Bool](repeating: false, count: s2.count)
        var matches = 0
        for i in 0..<s1.count {
            let start = max(0, i - window)
            let end = min(i + window + 1, s2.count)
            guard start < end else { continue }
            for j in start..<end where !s2Matched[j] && s1[i] == s2[j] {
                s1Matched[i] = true
                s2Matched[j] = true
                matches += 1
                break
            }
        }
        if matches == 0 { return 0 }

        var transpositions = 0
        var k = 0
        for i in 0..<s1.count where s1Matched[i] {
            while !s2Matched[k] { k += 1 }
            if s1[i] != s2[k] { transpositions += 1 }
            k += 1
        }
        let m = Double(matches)
        let jaro = (m / Double(s1.count) + m / Double(s2.count) + (m - Double(transpositions) / 2) / m) / 3

        var prefix = 0
        for i in 0..<min(4, s1.count, s2.count) {
            guard s1[i] == s2[i] else { break }
            prefix += 1
        }
        return jaro + Double(prefix) * prefixScale * (1 - jaro)
    }

    /// Levenshtein ratio after sorting words, so word order doesn't matter:
    /// `energy 52 cafe del mar` = `cafe del mar energy 52`.
    public static func tokenSortRatio(_ a: String, _ b: String) -> Double {
        levenshteinRatio(sortedTokens(a), sortedTokens(b))
    }

    /// Score for the *Similar* level: close spelling, same word order.
    public static func similar(_ a: String, _ b: String) -> Double {
        levenshteinRatio(a, b)
    }

    /// Score for the *Fuzzy* level: forgiving of word order and differing endings.
    public static func fuzzy(_ a: String, _ b: String) -> Double {
        max(jaroWinkler(a, b), tokenSortRatio(a, b))
    }

    static func sortedTokens(_ s: String) -> String {
        s.split(separator: " ").sorted().joined(separator: " ")
    }
}
