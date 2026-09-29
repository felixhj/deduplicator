import Foundation
import Testing
@testable import DedupCore

@Suite struct NormaliserTests {
    private func normalise(
        _ title: String,
        _ artist: String,
        _ configure: (inout NormalisationOptions) -> Void = { _ in }
    ) -> NormalisedTags {
        var options = NormalisationOptions()
        configure(&options)
        return Normaliser(options: options).normalise(title: title, artist: artist)
    }

    // MARK: Defaults strip nothing

    @Test func defaultOnlyFoldsCaseAndWhitespace() {
        let n = normalise("  Strings of Life  (Original Mix) ", "Rhythim Is Rhythim ft. Derrick May")
        #expect(n.title == "strings of life (original mix)")
        #expect(n.primaryArtists == ["rhythim is rhythim ft. derrick may"])
        #expect(n.featuredArtists.isEmpty)
        #expect(n.removedFromTitle.isEmpty)
    }

    @Test func caseSensitiveWhenDisabled() {
        let n = normalise("Song", "Artist") { $0.ignoreCase = false }
        #expect(n.title == "Song")
        #expect(n.artist == "Artist")
    }

    // MARK: Version stripping

    @Test func neutralOnlyStripsOriginalMixButKeepsRemix() {
        let original = normalise("Strings of Life (Original Mix)", "Rhythim Is Rhythim") { $0.versionStripping = .neutralOnly }
        let remix = normalise("Strings of Life (Carl Craig Remix)", "Rhythim Is Rhythim") { $0.versionStripping = .neutralOnly }
        #expect(original.title == "strings of life")
        #expect(original.removedFromTitle == ["Original Mix"])
        #expect(remix.title == "strings of life (carl craig remix)")
    }

    @Test func allVersionsStripsRemixes() {
        let remix = normalise("Strings of Life (Carl Craig Remix)", "X") { $0.versionStripping = .allVersions }
        #expect(remix.title == "strings of life")
    }

    @Test func versionStrippingKeepsNonVersionBrackets() {
        let n = normalise("Symphony (Part 2) (Extended Mix)", "X") { $0.versionStripping = .allVersions }
        #expect(n.title == "symphony (part 2)")
    }

    @Test func dashSuffixVersions() {
        let n = normalise("Song – Radio Edit", "X") { $0.versionStripping = .neutralOnly }
        #expect(n.title == "song")
        let kept = normalise("Song - Dub", "X") { $0.versionStripping = .neutralOnly }
        #expect(kept.title == "song - dub")
        let notVersion = normalise("Song - Part 2", "X") { $0.versionStripping = .allVersions }
        #expect(notVersion.title == "song - part 2")
    }

    @Test func stripAllBracketsRemovesEverything() {
        let n = normalise("Song [Love Theme] (Part 2)", "X") { $0.stripAllBrackets = true }
        #expect(n.title == "song")
    }

    @Test func neverStripsTitleToNothing() {
        let n = normalise("(Intro)", "X") { $0.stripAllBrackets = true }
        #expect(n.title == "(intro)")
        let m = normalise("(Original Mix)", "X") { $0.versionStripping = .neutralOnly }
        #expect(m.title == "(original mix)")
    }

    // MARK: Featured artists

    @Test func featuredArtistInArtistTagIsSeparated() {
        let n = normalise("Song", "Rhythim Is Rhythim ft. Derrick May") { $0.separateFeaturedArtists = true }
        #expect(n.primaryArtists == ["rhythim is rhythim"])
        #expect(n.featuredArtists == ["derrick may"])
    }

    @Test func featuredArtistInTitleIsStripped() {
        let n = normalise("Song (feat. B) (Original Mix)", "A") {
            $0.stripFeaturedFromTitle = true
            $0.versionStripping = .neutralOnly
        }
        #expect(n.title == "song")
        #expect(n.primaryArtists == ["a"])
        #expect(n.featuredArtists == ["b"])
    }

    // MARK: Collaborations and "The"

    @Test func collaborationsAreOrderIndependent() {
        let a = normalise("Song", "A & B") { $0.splitCollaborations = true }
        let b = normalise("Song", "B, A") { $0.splitCollaborations = true }
        #expect(a.primaryArtists == ["a", "b"])
        #expect(a.primaryArtists == b.primaryArtists)
    }

    @Test func leadingTheIgnored() {
        let a = normalise("Firestarter", "The Prodigy") { $0.ignoreLeadingThe = true }
        let b = normalise("Firestarter", "Prodigy") { $0.ignoreLeadingThe = true }
        #expect(a.artist == b.artist)
    }

    // MARK: Title clean-up

    @Test func trackNumberPrefixStripped() {
        let n = normalise("01 - Song", "A") { $0.stripTrackNumberPrefix = true }
        #expect(n.title == "song")
        #expect(n.removedFromTitle == ["01"])
    }

    @Test func artistInTitleSplitWhenArtistMatches() {
        let n = normalise("Derrick May - Strings of Life", "derrick may") { $0.splitArtistFromTitle = true }
        #expect(n.title == "strings of life")
        #expect(n.artist == "derrick may")
    }

    @Test func artistInTitleFillsEmptyArtist() {
        let n = normalise("Derrick May - Strings of Life", "") { $0.splitArtistFromTitle = true }
        #expect(n.title == "strings of life")
        #expect(n.artist == "derrick may")
    }

    @Test func artistInTitleLeftAloneWhenArtistDiffers() {
        let n = normalise("Song - Part 2", "Someone") { $0.splitArtistFromTitle = true }
        #expect(n.title == "song - part 2")
    }

    @Test func filenameFallback() {
        var options = NormalisationOptions()
        options.filenameFallback = true
        let n = Normaliser(options: options).normalise(title: "", artist: "", fileStem: "03 - Energy 52 - Cafe del Mar")
        #expect(n.title == "cafe del mar")
        #expect(n.artist == "energy 52")
    }

    @Test func filenameFallbackIgnoredWhenTitlePresent() {
        var options = NormalisationOptions()
        options.filenameFallback = true
        let n = Normaliser(options: options).normalise(title: "Real Title", artist: "", fileStem: "Other - Thing")
        #expect(n.title == "real title")
    }

    // MARK: Folding

    @Test func foldingOptions() {
        let n = normalise("Café  Del Mar – Don’t Stop!", "Energy 52") {
            $0.foldDiacritics = true
            $0.ignorePunctuation = true
        }
        #expect(n.title == "cafe del mar dont stop")
    }

    @Test func ignoreSpaces() {
        let a = normalise("Song", "Energy 52") { $0.ignoreSpaces = true }
        let b = normalise("Song", "Energy52") { $0.ignoreSpaces = true }
        #expect(a.artist == b.artist)
    }

    // MARK: Presets on real-world pairs

    @Test(arguments: [
        (("Strings of Life", "Rhythim Is Rhythim"), ("Strings of Life (Original Mix)", "Rhythim Is Rhythim ft. Derrick May")),
        (("Cafe del Mar", "Energy 52"), ("Café Del Mar (Extended Mix)", "Energy 52")),
        (("Firestarter", "The Prodigy"), ("01 - Firestarter", "Prodigy")),
        (("Song", "A & B"), ("Song (feat. C) [Radio Edit]", "B and A")),
        (("Song", "Artist"), ("Artist - Song", "Artist")),
        (("Don't Stop", "Artist"), ("Don’t Stop - Remastered 2011", "Artist")),
    ])
    func djPresetMatchesRealWorldPairs(a: (String, String), b: (String, String)) {
        let normaliser = Normaliser(options: .djLibrary)
        let na = normaliser.normalise(title: a.0, artist: a.1)
        let nb = normaliser.normalise(title: b.0, artist: b.1)
        #expect(na.title == nb.title)
        #expect(na.primaryArtists == nb.primaryArtists)
    }

    @Test func djPresetKeepsRemixesApart() {
        let normaliser = Normaliser(options: .djLibrary)
        let a = normaliser.normalise(title: "Song (Original Mix)", artist: "A")
        let b = normaliser.normalise(title: "Song (Dub Mix)", artist: "A")
        #expect(a.title != b.title)
    }

    @Test func normalisesTrack() {
        let track = Track(id: 1, url: URL(fileURLWithPath: "/music/A - B.mp3"), title: "B (Original Mix)", artist: "A")
        let n = Normaliser(options: .djLibrary).normalise(track)
        #expect(n.title == "b")
        #expect(n.artist == "a")
    }
}
