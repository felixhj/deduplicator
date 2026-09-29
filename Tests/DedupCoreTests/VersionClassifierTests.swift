import Testing
@testable import DedupCore

@Suite struct VersionClassifierTests {
    @Test(arguments: [
        "Original Mix", "Extended Mix", "Radio Edit", "Album Version", "Remastered",
        "2011 Remaster", "Remastered 2009 Version", "Explicit", "Clean", "Mono",
        "Extended Version", "Single Edit", "Mixed", "12\" Version", "Edit",
        "Digitally Remastered", "Re-Mastered",
    ])
    func neutral(fragment: String) {
        #expect(VersionClassifier.classify(fragment) == .neutral)
    }

    @Test(arguments: [
        "Carl Craig Remix", "Dub", "VIP", "Live at Wembley", "Acoustic", "Instrumental",
        "Club Mix", "Vocal Mix", "Joe Smith Edit", "Re-Edit", "Rework", "Bootleg",
        "Extended Club Mix", "Dub Mix", "Spanish Version", "Acapella", "RMX",
    ])
    func distinct(fragment: String) {
        #expect(VersionClassifier.classify(fragment) == .distinct)
    }

    @Test(arguments: ["Part 2", "Interlude", "Love Theme", "", "The", "Pt. 1", "Intro"])
    func notAVersion(fragment: String) {
        #expect(VersionClassifier.classify(fragment) == .notAVersion)
    }
}
