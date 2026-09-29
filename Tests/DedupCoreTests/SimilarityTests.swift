import Testing
@testable import DedupCore

@Suite struct SimilarityTests {
    @Test func levenshteinDistance() {
        #expect(Similarity.levenshteinDistance("kitten", "sitting") == 3)
        #expect(Similarity.levenshteinDistance("", "abc") == 3)
        #expect(Similarity.levenshteinDistance("same", "same") == 0)
    }

    @Test func levenshteinRatio() {
        #expect(Similarity.levenshteinRatio("abc", "abc") == 1)
        #expect(Similarity.levenshteinRatio("", "") == 1)
        #expect(abs(Similarity.levenshteinRatio("kitten", "sitting") - (1 - 3.0 / 7)) < 1e-9)
    }

    @Test func jaroWinklerReferenceValues() {
        #expect(abs(Similarity.jaroWinkler("MARTHA", "MARHTA") - 0.9611) < 0.001)
        #expect(abs(Similarity.jaroWinkler("DWAYNE", "DUANE") - 0.84) < 0.001)
        #expect(abs(Similarity.jaroWinkler("DIXON", "DICKSONX") - 0.8133) < 0.001)
        #expect(Similarity.jaroWinkler("abc", "") == 0)
        #expect(Similarity.jaroWinkler("abc", "xyz") == 0)
    }

    @Test func tokenSortIgnoresWordOrder() {
        #expect(Similarity.tokenSortRatio("energy 52 cafe del mar", "cafe del mar energy 52") == 1)
    }

    @Test func similarIsStricterThanFuzzy() {
        let a = "strings of life", b = "strings of life extended"
        #expect(Similarity.similar(a, b) < 0.9)
        #expect(Similarity.fuzzy(a, b) >= 0.8)
    }

    @Test func typoIsSimilar() {
        #expect(Similarity.similar("rhythim is rhythim", "rhythm is rhythm") >= 0.85)
    }
}
