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
}
