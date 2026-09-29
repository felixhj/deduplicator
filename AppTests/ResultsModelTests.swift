import DedupCore
import Foundation
import Testing
@testable import Deduplicator

@MainActor
struct ResultsModelTests {
    let storage = TestDefaults()

    func loadedModel() async throws -> ResultsModel {
        let model = ResultsModel(defaults: storage.defaults)
        model.load(Fixtures.library)
        try await waitForMatching(model)
        return model
    }

    @Test func loadingFindsGroupsAndTagKeys() async throws {
        let model = try await loadedModel()
        #expect(model.groups.count == 2)
        #expect(model.shownGroups.map(\.trackIDs) == [[0, 1, 2], [3, 4]])
        #expect(model.tagKeys == ["INITIALKEY"])
        #expect(model.shownCopyCount == 5)
    }

    @Test func startsWithStandardSettingsAndDefaultColumns() {
        let model = ResultsModel(defaults: storage.defaults)
        #expect(model.criteria == .standard)
        #expect(model.columns == TrackColumn.defaults)
        #expect(model.matchState == .idle)
    }

    @Test func marks() async throws {
        let model = try await loadedModel()
        let group = model.shownGroups[1]
        model.setMarked([3], true)
        #expect(model.marked == [3])
        #expect(!model.isEveryCopyMarked(in: group))
        model.toggleMark(4)
        #expect(model.isEveryCopyMarked(in: group))
        #expect(model.markedSize == 50_000_000)
        let revision = model.marksRevision
        model.setMarked([3, 4], true)
        #expect(model.marksRevision == revision, "Marking what's already marked changes nothing")
        model.setMarked([3, 4], false)
        #expect(model.marked.isEmpty)
    }

    @Test func loadingNewTracksClearsMarks() async throws {
        let model = try await loadedModel()
        model.setMarked([0], true)
        model.load(Fixtures.library)
        #expect(model.marked.isEmpty)
    }

    @Test func marksOnCopiesThatLeaveEveryGroupAreDropped() async throws {
        let model = try await loadedModel()
        model.setMarked([1, 3], true)
        // Identical titles are case-sensitive, so "Strings Of Life" leaves its group.
        model.criteria.title = FieldRule(.identical)
        try await Task.sleep(for: .milliseconds(350))
        try await waitForMatching(model)
        #expect(model.shownGroups.map(\.trackIDs) == [[0, 2], [3, 4]])
        #expect(model.marked == [3])
    }

    @Test func filterAndOrderRearrangeGroups() async throws {
        let model = try await loadedModel()
        let revision = model.revision
        model.filter.text = "cafe"
        #expect(model.shownGroups.map(\.trackIDs) == [[3, 4]])
        #expect(model.revision > revision)
        model.filter.text = ""
        model.order = .column(.bitrate, ascending: false)
        #expect(model.shownGroups.map(\.trackIDs) == [[0, 1, 2], [3, 4]])
        model.order = .column(.bitrate, ascending: true)
        #expect(model.shownGroups.map(\.trackIDs) == [[2, 1, 0], [4, 3]])
    }

    @Test func settingsAreKeptForNextTime() {
        let first = ResultsModel(defaults: storage.defaults)
        first.criteria = .djLibrary
        first.columns = [.title, .tag("BPM")]
        first.columnWidths = ["title": 300]

        let second = ResultsModel(defaults: storage.defaults)
        #expect(second.criteria == .djLibrary)
        #expect(second.columns == [.title, .tag("BPM")])
        #expect(second.columnWidths == ["title": 300])
    }

    @Test func unreadableSavedSettingsFallBackToStandard() {
        storage.defaults.set(Data("not json".utf8), forKey: "matchCriteria")
        #expect(ResultsModel(defaults: storage.defaults).criteria == .standard)
    }

    @Test func togglingAndRestoringColumns() {
        let model = ResultsModel(defaults: storage.defaults)
        model.toggleColumn(.tag("INITIALKEY"))
        #expect(model.columns.last == .tag("INITIALKEY"))
        model.toggleColumn(.title)
        #expect(!model.columns.contains(.title))
        model.columnWidths = ["path": 500]
        model.restoreDefaultColumns()
        #expect(model.columns == TrackColumn.defaults)
        #expect(model.columnWidths.isEmpty)
    }

    // MARK: - Removing and auto-select

    @Test func removingCopiesTakesThemOutOfGroupsMarksAndSelection() async throws {
        let model = try await loadedModel()
        model.setMarked([1, 3], true)
        model.selection = [0, 1]
        let revision = model.revision
        model.remove([1, 3])
        #expect(model.shownGroups.map(\.trackIDs) == [[0, 2]])
        #expect(model.marked.isEmpty)
        #expect(model.selection == [0])
        #expect(model.tracks[1] == nil)
        #expect(model.revision > revision)

        // Matching again doesn't bring them back.
        model.criteria.durationTolerance = 10
        try await Task.sleep(for: .milliseconds(350))
        try await waitForMatching(model)
        #expect(model.groups.map(\.trackIDs) == [[0, 2]])
    }

    @Test func restoredCopiesAreMatchedAgain() async throws {
        let model = try await loadedModel()
        model.remove([1, 3])
        model.restore(Fixtures.library.filter { [1, 3].contains($0.id) })
        try await waitForMatching(model)
        #expect(model.shownGroups.map(\.trackIDs) == [[0, 1, 2], [3, 4]])
    }

    @Test func removingWhileMatchingMatchesAgainWithout() async throws {
        let model = ResultsModel(defaults: storage.defaults)
        model.load(Fixtures.library)
        model.remove([1])
        try await waitForMatching(model)
        #expect(model.groups.map(\.trackIDs) == [[0, 2], [3, 4]])
    }

    @Test func autoSelectKeepsTheBestCopyInEachShownGroup() async throws {
        let model = try await loadedModel()
        model.setMarked([0], true)
        let choices = model.keeperChoices()
        #expect(choices.map(\.keeper) == [0, 3], "Lossless copies win")
        model.apply(choices)
        #expect(model.marked == [1, 2, 4], "Marks made by hand in those groups are replaced")

        model.unmarkAll()
        #expect(model.marked.isEmpty)
        model.filter.text = "cafe"
        model.apply(model.keeperChoices())
        #expect(model.marked == [4], "Groups the filter hides are left alone")
    }

    @Test func keeperRulesAreSaved() {
        let model = ResultsModel(defaults: storage.defaults)
        #expect(model.keeperRules == KeeperSelector.defaultRules)
        model.keeperRules = [.pathContains("Library"), .newerFile]
        #expect(ResultsModel(defaults: storage.defaults).keeperRules == [.pathContains("Library"), .newerFile])
    }

    @Test func eachScanIsANewGeneration() {
        let model = ResultsModel(defaults: storage.defaults)
        model.load(Fixtures.library)
        let first = model.generation
        model.load(Fixtures.library)
        #expect(model.generation == first + 1)
    }

    @Test func updatingACopyShowsItsNewValues() async throws {
        let model = try await loadedModel()
        var track = try #require(model.tracks[1])
        track.comment = "Ripped"
        track.tags["MOOD"] = "Euphoric"
        let revision = model.revision
        model.update(track)
        #expect(model.tracks[1]?.comment == "Ripped")
        #expect(model.tagKeys.contains("MOOD"))
        #expect(model.revision > revision)
        model.filter.text = "euphoric"
        #expect(model.shownGroups.isEmpty, "The filter doesn't search tags beyond the main fields")
        model.filter.text = "strings"
        #expect(model.shownGroups.count == 1)
    }

    @Test func copiesInAGroup() async throws {
        let model = try await loadedModel()
        #expect(model.copies(inGroupOf: 4).map(\.id) == [3, 4])
        #expect(model.copies(inGroupOf: 5).isEmpty, "Not in any group")
    }

    // MARK: - Remembered between launches

    @Test func orderAndMinimumConfidenceAreRememberedButNotTheText() {
        let model = ResultsModel(defaults: storage.defaults)
        model.order = .column(.bitrate, ascending: false)
        model.filter = ResultFilter(text: "cafe", minimumConfidence: 0.9)
        let reopened = ResultsModel(defaults: storage.defaults)
        #expect(reopened.order == .column(.bitrate, ascending: false))
        #expect(reopened.filter.minimumConfidence == 0.9)
        #expect(reopened.filter.text.isEmpty)

        model.order = .column(.tag("COMMENT:ITUNNORM"), ascending: true)
        #expect(ResultsModel(defaults: storage.defaults).order == .column(.tag("COMMENT:ITUNNORM"), ascending: true))
        model.order = .copies
        #expect(ResultsModel(defaults: storage.defaults).order == .copies)
    }

    @Test func savedPresetsAreRemembered() {
        let model = ResultsModel(defaults: storage.defaults)
        #expect(model.savedPresets.isEmpty)
        model.savedPresets = [SavedPreset(name: "Strict", criteria: .standard)]
        #expect(ResultsModel(defaults: storage.defaults).savedPresets == [SavedPreset(name: "Strict", criteria: .standard)])
    }

    @Test func presetsAreSavedByNameAndRecognised() {
        var loose = MatchCriteria.standard
        loose.durationTolerance = 9
        var presets = SavedPreset.list([], saving: loose, as: "  Nine seconds ")
        presets = SavedPreset.list(presets, saving: .djLibrary, as: "A DJ copy")
        #expect(presets.map(\.name) == ["A DJ copy", "Nine seconds"])
        #expect(SavedPreset.list(presets, saving: .standard, as: "   ") == presets, "A blank name saves nothing")
        presets = SavedPreset.list(presets, saving: .loose, as: "Nine seconds")
        #expect(presets.count == 2 && presets.last?.criteria == .loose, "The same name replaces")

        #expect(PresetChoice(matching: .djLibrary, saved: presets) == .builtIn(.djLibrary), "Built-in presets come first")
        #expect(PresetChoice(matching: .loose, saved: presets) == .builtIn(.loose))
        #expect(PresetChoice(matching: loose, saved: SavedPreset.list([], saving: loose, as: "Nine")) == .saved("Nine"))
        #expect(PresetChoice(matching: loose, saved: []) == .custom)
    }

    @Test func groupsWithEveryCopyMarkedAreFound() async throws {
        let model = try await loadedModel()
        #expect(model.groupsWithEveryCopyMarked.isEmpty)
        model.setMarked([3, 4, 0], true)
        #expect(model.groupsWithEveryCopyMarked.map(\.trackIDs) == [[3, 4]])
        model.reveal(4)
        #expect(model.revealRequest?.trackID == 4)
    }

    @Test func theEveryCopyCalloutListsTracksBriefly() {
        #expect(EveryCopyCallout.list(["A"]) == "“A”")
        #expect(EveryCopyCallout.list(["A", "B"]) == "“A” and “B”")
        #expect(EveryCopyCallout.list(["A", "B", "C"]) == "“A”, “B” and “C”")
        #expect(EveryCopyCallout.list(["A", "B", "C", "D", "E"]) == "“A”, “B”, “C” and 2 more")
    }
}
