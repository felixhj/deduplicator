import Testing
@testable import DedupCore

@Suite struct CreditParserTests {
    // MARK: Featured artists

    @Test(arguments: [
        ("A ft. B", ("A", "B")),
        ("A feat. B", ("A", "B")),
        ("A Feat B", ("A", "B")),
        ("A featuring B & C", ("A", "B & C")),
        ("A (feat. B)", ("A", "B")),
        ("A [ft. B]", ("A", "B")),
        ("Song (feat. B) (Original Mix)", ("Song (Original Mix)", "B")),
        ("Song feat. B [Radio Edit]", ("Song [Radio Edit]", "B")),
        ("A FT. B", ("A", "B")),
    ])
    func splitsFeatured(input: String, expected: (String, String)) {
        let result = CreditParser.splitFeatured(input)
        #expect(result.main == expected.0)
        #expect(result.featured == expected.1)
    }

    @Test(arguments: [
        "Ft Worth Band",   // marker as the first word is a name
        "Left Feet",       // "feet" isn't a marker
        "Daft Punk",
        "Soft Cell",
        "A ft.",           // nothing after the marker
    ])
    func leavesNonFeatured(input: String) {
        let result = CreditParser.splitFeatured(input)
        #expect(result.featured == nil)
    }

    // MARK: Collaborations

    @Test(arguments: [
        ("A & B", ["A", "B"]),
        ("A and B", ["A", "B"]),
        ("A x B", ["A", "B"]),
        ("A vs. B", ["A", "B"]),
        ("A, B & C", ["A", "B", "C"]),
        ("A / B", ["A", "B"]),
        ("AC/DC", ["AC/DC"]),
        ("Malcolm X", ["Malcolm X"]),
        ("Solo Artist", ["Solo Artist"]),
        ("& Leading", ["& Leading"]),
        ("A & , B", ["A", "B"]),
    ])
    func splitsCollaborators(input: String, expected: [String]) {
        #expect(CreditParser.splitCollaborators(input) == expected)
    }

    // MARK: Track number prefixes

    @Test(arguments: [
        ("01 - Song", "Song"),
        ("01. Song", "Song"),
        ("1. Song", "Song"),
        ("1) Song", "Song"),
        ("01_Song", "Song"),
        ("1-01 Song", "Song"),
        ("01 Song", "Song"),
        ("12 – Song", "Song"),
        ("01 -Song", "Song"),
    ])
    func removesTrackNumber(input: String, expected: String) {
        #expect(CreditParser.removingTrackNumberPrefix(input) == expected)
    }

    @Test(arguments: [
        "99 Luftballons",
        "7 Seconds",
        "1999",
        "2-4-6-8 Motorway",
        "2.5 Hours",
        "Song",
        "01 - 02",
        "808 State",
    ])
    func keepsTitlesThatStartWithNumbers(input: String) {
        #expect(CreditParser.removingTrackNumberPrefix(input) == input)
    }
}
