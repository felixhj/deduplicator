import Foundation
import Testing
@testable import DedupCore

/// Builds tracks with unique IDs.
final class TrackFactory {
    private var nextID = 0

    func callAsFunction(
        _ title: String,
        _ artist: String,
        duration: Double? = 300,
        trackNumber: Int? = nil,
        album: String = "",
        format: AudioFormat = .mp3
    ) -> Track {
        nextID += 1
        return Track(
            id: nextID,
            url: URL(fileURLWithPath: "/music/\(nextID).mp3"),
            title: title,
            artist: artist,
            album: album,
            trackNumber: trackNumber,
            duration: duration,
            audio: AudioProperties(format: format)
        )
    }
}

@Suite struct MatchEngineTests {
    private func groups(_ tracks: [Track], _ criteria: MatchCriteria) async throws -> [[Track.ID]] {
        try await MatchEngine(criteria: criteria).findDuplicates(in: tracks).map { $0.trackIDs.sorted() }
    }

    // MARK: Basic levels

    @Test func sameLevelMatchesCaseDifferences() async throws {
        let track = TrackFactory()
        let a = track("Strings of Life", "Rhythim Is Rhythim")
        let b = track("strings of life", "RHYTHIM IS RHYTHIM")
        let c = track("Nude Photo", "Rhythim Is Rhythim")
        let result = try await groups([a, b, c], .standard)
        #expect(result == [[a.id, b.id]])
    }

    @Test func identicalLevelIsCaseSensitive() async throws {
        let track = TrackFactory()
        var criteria = MatchCriteria()
        criteria.title = FieldRule(.identical)
        let a = track("Strings of Life", "X")
        let b = track("strings of life", "X")
        #expect(try await groups([a, b], criteria).isEmpty)
    }

    @Test func emptyTitlesNeverMatch() async throws {
        let track = TrackFactory()
        let a = track("", "X")
        let b = track("", "X")
        #expect(try await groups([a, b], .standard).isEmpty)
    }

    // MARK: Smart normalisation

    @Test func originalMixAndFeaturedArtistMatchWithDJPreset() async throws {
        let track = TrackFactory()
        let a = track("Strings of Life", "Rhythim Is Rhythim")
        let b = track("Strings of Life (Original Mix)", "Rhythim Is Rhythim ft. Derrick May")
        let remix = track("Strings of Life (Carl Craig Remix)", "Rhythim Is Rhythim")
        let result = try await MatchEngine(criteria: .djLibrary).findDuplicates(in: [a, b, remix])
        #expect(result.map { $0.trackIDs.sorted() } == [[a.id, b.id]])
        #expect(result[0].reasons.contains(.versionTextIgnored))
        #expect(result[0].reasons.contains(.featuredArtistIgnored))
    }

    @Test func defaultCriteriaDoNotStripVersions() async throws {
        let track = TrackFactory()
        let a = track("Strings of Life", "Rhythim Is Rhythim")
        let b = track("Strings of Life (Original Mix)", "Rhythim Is Rhythim")
        #expect(try await groups([a, b], .standard).isEmpty)
    }

    // MARK: Similar and fuzzy

    @Test func similarCatchesTypos() async throws {
        let track = TrackFactory()
        var criteria = MatchCriteria()
        criteria.title = FieldRule(.similar, threshold: 0.85)
        let a = track("Cafe del Mar", "Energy 52")
        let b = track("Cafe del Marr", "Energy 52")
        #expect(try await groups([a, b], criteria) == [[a.id, b.id]])
    }

    @Test func fuzzyOnBothFieldsUsesTokenBlocking() async throws {
        let track = TrackFactory()
        var criteria = MatchCriteria()
        criteria.title = FieldRule(.fuzzy)
        criteria.artist = FieldRule(.fuzzy)
        let a = track("Cafe del Mar", "Energy 52")
        let b = track("Cafe del Mar (Three N One Mix)", "Energy 52")
        let c = track("Totally Different", "Someone Else")
        #expect(try await groups([a, b, c], criteria) == [[a.id, b.id]])
    }

    @Test func thresholdIsRespected() async throws {
        let track = TrackFactory()
        var criteria = MatchCriteria()
        criteria.title = FieldRule(.similar, threshold: 0.99)
        let a = track("Cafe del Mar", "Energy 52")
        let b = track("Cafe del Marr", "Energy 52")
        #expect(try await groups([a, b], criteria).isEmpty)
    }

    // MARK: Artists

    @Test func collaborationOrderDoesNotMatter() async throws {
        let track = TrackFactory()
        var criteria = MatchCriteria()
        criteria.normalisation.splitCollaborations = true
        let a = track("Song", "A & B")
        let b = track("Song", "B, A")
        #expect(try await groups([a, b], criteria) == [[a.id, b.id]])
    }

    @Test func artistSubsetOption() async throws {
        let track = TrackFactory()
        var criteria = MatchCriteria()
        criteria.normalisation.splitCollaborations = true
        let a = track("Song", "A")
        let b = track("Song", "A & B")
        #expect(try await groups([a, b], criteria).isEmpty)
        criteria.artistSubsetMatches = true
        #expect(try await groups([a, b], criteria) == [[a.id, b.id]])
    }

    @Test func ignoredArtist() async throws {
        let track = TrackFactory()
        var criteria = MatchCriteria()
        criteria.artist = FieldRule(.ignore)
        let a = track("Song", "A")
        let b = track("Song", "Completely Different")
        #expect(try await groups([a, b], criteria) == [[a.id, b.id]])
    }

    @Test func swappedFields() async throws {
        let track = TrackFactory()
        var criteria = MatchCriteria()
        let a = track("Strings of Life", "Derrick May")
        let b = track("Derrick May", "Strings of Life")
        #expect(try await groups([a, b], criteria).isEmpty)
        criteria.detectSwappedFields = true
        let result = try await MatchEngine(criteria: criteria).findDuplicates(in: [a, b])
        #expect(result.map { $0.trackIDs.sorted() } == [[a.id, b.id]])
        #expect(result[0].reasons.contains(.swappedTitleAndArtist))
    }

    // MARK: Constraints

    @Test func durationTolerance() async throws {
        let track = TrackFactory()
        var criteria = MatchCriteria()
        criteria.durationTolerance = 2
        let a = track("Song", "A", duration: 300)
        let b = track("Song", "A", duration: 301.5)
        let c = track("Song", "A", duration: 420)
        #expect(try await groups([a, b, c], criteria) == [[a.id, b.id]])
    }

    @Test func unknownDurationPasses() async throws {
        let track = TrackFactory()
        let a = track("Song", "A", duration: 300)
        let b = track("Song", "A", duration: nil)
        #expect(try await groups([a, b], .standard) == [[a.id, b.id]])
    }

    @Test func durationCheckCanBeSwitchedOff() async throws {
        let track = TrackFactory()
        var criteria = MatchCriteria()
        criteria.durationTolerance = nil
        let a = track("Song", "A", duration: 300)
        let b = track("Song", "A", duration: 600)
        #expect(try await groups([a, b], criteria) == [[a.id, b.id]])
    }

    @Test func trackNumberConstraint() async throws {
        let track = TrackFactory()
        var criteria = MatchCriteria()
        let a = track("Song", "A", trackNumber: 1)
        let b = track("Song", "A", trackNumber: 1)
        let c = track("Song", "A", trackNumber: 5)

        criteria.trackNumber = .same
        #expect(try await groups([a, b, c], criteria) == [[a.id, b.id]])

        // c differs from both a and b, so it anchors a group of all three.
        criteria.trackNumber = .different
        #expect(try await groups([a, b, c], criteria) == [[a.id, b.id, c.id]])
    }

    @Test func albumConstraint() async throws {
        let track = TrackFactory()
        var criteria = MatchCriteria()
        criteria.album = .different
        let a = track("Song", "A", album: "Album")
        let b = track("Song", "A", album: "album")
        let c = track("Song", "A", album: "Compilation")
        let result = try await groups([a, b, c], criteria)
        #expect(result.allSatisfy { $0.contains(c.id) })
    }

    @Test func formatConstraint() async throws {
        let track = TrackFactory()
        var criteria = MatchCriteria()
        criteria.format = .different
        let a = track("Song", "A", format: .mp3)
        let b = track("Song", "A", format: .mp3)
        #expect(try await groups([a, b], criteria).isEmpty)
        let c = track("Song", "A", format: .flac)
        #expect(try await groups([a, c], criteria) == [[a.id, c.id]])
    }

    @Test func extraFieldRule() async throws {
        let track = TrackFactory()
        var criteria = MatchCriteria()
        criteria.extraFields = [ExtraFieldRule(.album, FieldRule(.same))]
        let a = track("Song", "A", album: "One")
        let b = track("Song", "A", album: "Two")
        #expect(try await groups([a, b], criteria).isEmpty)
    }

    // MARK: Grouping

    @Test func groupsOfThree() async throws {
        let track = TrackFactory()
        let a = track("Song", "A")
        let b = track("song", "a")
        let c = track("SONG", "A")
        #expect(try await groups([a, b, c], .standard) == [[a.id, b.id, c.id]])
    }

    @Test func anchorCheckBreaksChains() async throws {
        let track = TrackFactory()
        var criteria = MatchCriteria()
        criteria.durationTolerance = 3
        // a≈b and b≈c by duration, but a and c are 4 s apart.
        let a = track("Song", "A", duration: 300)
        let b = track("Song", "A", duration: 302)
        let c = track("Song", "A", duration: 304)
        let anchored = try await groups([a, b, c], criteria)
        #expect(anchored.count == 1)
        #expect(anchored[0].contains(b.id))
        #expect(anchored[0].count == 3)

        let d = track("Song", "A", duration: 306)
        // a–b–c–d chain: b anchors {a, b, c}; d only matches c, which is
        // already taken, so it's left out rather than chained on.
        #expect(try await groups([a, b, c, d], criteria) == [[a.id, b.id, c.id]])

        criteria.requireAnchorMatch = false
        #expect(try await groups([a, b, c, d], criteria) == [[a.id, b.id, c.id, d.id]])
    }

    @Test func confidenceIsHigherForExactMatches() async throws {
        let track = TrackFactory()
        var criteria = MatchCriteria()
        criteria.title = FieldRule(.fuzzy, threshold: 0.7)
        let a = track("Song Title", "A", duration: 300)
        let b = track("Song Title", "A", duration: 300)
        let c = track("Song Titel", "B", duration: 400)
        let d = track("Song Titel", "B", duration: 400)
        let e = track("Song Tittle", "B", duration: 401)
        let result = try await MatchEngine(criteria: criteria).findDuplicates(in: [a, b, c, d, e])
        let exact = try #require(result.first { $0.trackIDs.contains(a.id) })
        let fuzzy = try #require(result.first { $0.trackIDs.contains(e.id) })
        #expect(exact.confidence == 1)
        #expect(fuzzy.confidence < 1)
    }

    @Test func directMatch() {
        let track = TrackFactory()
        let a = track("Song", "A")
        let b = track("song", "a")
        let result = MatchEngine().match(a, b)
        #expect(result != nil)
        #expect(result?.reasons.contains(.sameTitle) == true)
    }

    // MARK: Scale

    @Test(.timeLimit(.minutes(1)))
    func fiftyThousandTracks() async throws {
        let words = ["love", "night", "dream", "fire", "heart", "light", "dance", "time", "soul", "star",
                     "rain", "city", "blue", "gold", "wild", "home", "run", "sky", "sun", "moon"]
        var generator = SplitMix64(seed: 42)
        var tracks: [Track] = []
        tracks.reserveCapacity(50_000)
        for id in 0..<50_000 {
            let title = (0..<3).map { _ in words[Int(generator.next() % UInt64(words.count))] }.joined(separator: " ")
            let artist = "Artist \(generator.next() % 5_000)"
            tracks.append(Track(
                id: id,
                url: URL(fileURLWithPath: "/music/\(id).mp3"),
                title: title,
                artist: artist,
                duration: Double(180 + generator.next() % 240)
            ))
        }
        // Plant known duplicates.
        for id in 0..<500 {
            var copy = tracks[id]
            copy.id = 100_000 + id
            copy.title += " (Original Mix)"
            tracks.append(copy)
        }

        let result = try await MatchEngine(criteria: .djLibrary).findDuplicates(in: tracks)
        let found = Set(result.flatMap(\.trackIDs))
        #expect((0..<500).allSatisfy { found.contains(100_000 + $0) })
    }
}

/// Deterministic random numbers for reproducible tests.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
