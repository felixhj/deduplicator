import Testing
@testable import DedupCore

@Suite struct TextFoldingTests {
    @Test(arguments: [
        ("  Energy   52 ", "Energy 52"),
        ("A\u{00A0}B", "A B"),
        ("", ""),
    ])
    func collapseWhitespace(input: String, expected: String) {
        #expect(TextFolding.collapseWhitespace(input) == expected)
    }

    @Test(arguments: [
        ("A – B — C", "A - B - C"),
        ("Don’t", "Don't"),
        ("“Quoted”", "\"Quoted\""),
        ("Plain", "Plain"),
    ])
    func unifyPunctuation(input: String, expected: String) {
        #expect(TextFolding.unifyPunctuation(input) == expected)
    }

    @Test(arguments: [
        ("Café Del Mar", "Cafe Del Mar"),
        ("Björk", "Bjork"),
        ("Røyksopp", "Royksopp"),
        ("Straße", "Strasse"),
        ("Sigur Rós", "Sigur Ros"),
        ("Beyoncé", "Beyonce"),
        ("No accents", "No accents"),
    ])
    func foldDiacritics(input: String, expected: String) {
        #expect(TextFolding.foldDiacritics(input) == expected)
    }

    @Test(arguments: [
        ("Simon & Garfunkel", "Simon and Garfunkel"),
        ("Florence + the Machine", "Florence and the Machine"),
        ("R&B", "R&B"),
    ])
    func ampersandToAnd(input: String, expected: String) {
        #expect(TextFolding.ampersandToAnd(input) == expected)
    }

    @Test(arguments: [
        ("Mr. Oizo", "Mr Oizo"),
        ("Don't Stop", "Dont Stop"),
        ("Hip-Hop!", "Hip Hop"),
        ("What's Up?", "Whats Up"),
        ("Plain Words", "Plain Words"),
    ])
    func stripPunctuation(input: String, expected: String) {
        #expect(TextFolding.stripPunctuation(input) == expected)
    }

    @Test(arguments: [
        ("The Prodigy", "Prodigy"),
        ("the xx", "xx"),
        ("Prodigy, The", "Prodigy"),
        ("The", "The"),
        ("Theatre of Tragedy", "Theatre of Tragedy"),
        ("Them Crooked Vultures", "Them Crooked Vultures"),
    ])
    func removingLeadingThe(input: String, expected: String) {
        #expect(TextFolding.removingLeadingThe(input) == expected)
    }

    @Test func splitOnSpacedDash() {
        #expect(TextFolding.splitOnSpacedDash("Song - Radio Edit") == ["Song", "Radio Edit"])
        #expect(TextFolding.splitOnSpacedDash("A – B — C") == ["A", "B", "C"])
        #expect(TextFolding.splitOnSpacedDash("Hip-Hop Hooray") == ["Hip-Hop Hooray"])
        #expect(TextFolding.splitOnSpacedDash("No dash") == ["No dash"])
    }
}
