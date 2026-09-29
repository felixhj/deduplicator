import DedupCore
import Foundation
import Observation

/// Duplicate groups for the last scan, and everything about how they're shown:
/// match settings, filter, order, columns and the copies marked for removal.
@MainActor
@Observable
final class ResultsModel {
    enum MatchState: Equatable {
        /// Nothing scanned yet.
        case idle
        case matching(progress: Double)
        case finished
    }

    private(set) var tracks: [Track.ID: Track] = [:]
    /// Every tag key in the scanned files, for the column picker.
    private(set) var tagKeys: [String] = []
    /// Groups as the engine found them.
    private(set) var groups: [DuplicateGroup] = []
    /// Groups after filtering and ordering, as the table shows them.
    private(set) var shownGroups: [DuplicateGroup] = []
    private(set) var matchState: MatchState = .idle
    /// Changes whenever `shownGroups` or `tracks` do, so the table knows to reload.
    private(set) var revision = 0

    var criteria: MatchCriteria {
        didSet {
            guard criteria != oldValue else { return }
            settings.criteria = criteria
            match(after: .milliseconds(300))
        }
    }

    var filter = ResultFilter() {
        didSet { if filter != oldValue { arrange() } }
    }

    var order: GroupOrder = .confidence {
        didSet { if order != oldValue { arrange() } }
    }

    /// Visible columns, in order.
    var columns: [TrackColumn] {
        didSet { if columns != oldValue { settings.columns = columns } }
    }

    /// Widths the user has set, by column ID.
    var columnWidths: [String: Double] {
        didSet { if columnWidths != oldValue { settings.columnWidths = columnWidths } }
    }

    /// Copies marked for removal.
    private(set) var marked: Set<Track.ID> = []
    /// Changes whenever `marked` does, so the table can refresh its tick boxes.
    private(set) var marksRevision = 0
    var selection: Set<Track.ID> = []

    @ObservationIgnored private var trackList: [Track] = []
    @ObservationIgnored private var searchIndex = SearchIndex()
    @ObservationIgnored private var matchTask: Task<Void, Never>?
    @ObservationIgnored private var matchID = UUID()
    @ObservationIgnored private let settings: ResultsSettings

    init(defaults: UserDefaults = .standard) {
        settings = ResultsSettings(defaults: defaults)
        criteria = settings.criteria
        columns = settings.columns
        columnWidths = settings.columnWidths
    }

    /// Takes the tracks from a new scan. Marks are cleared, because track IDs
    /// belong to one scan.
    func load(_ tracks: [Track]) {
        trackList = tracks
        self.tracks = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        searchIndex = SearchIndex(tracks: tracks)
        tagKeys = Set(tracks.flatMap(\.tags.keys)).sorted()
        marked = []
        marksRevision += 1
        selection = []
        match()
    }

    // MARK: - Matching

    /// Finds duplicates again, after `delay` so a slider being dragged doesn't
    /// start a run for every step. A run already going is cancelled.
    func match(after delay: Duration = .zero) {
        matchTask?.cancel()
        guard !trackList.isEmpty else {
            groups = []
            matchState = .idle
            arrange()
            return
        }
        let id = UUID()
        matchID = id
        matchState = .matching(progress: 0)
        let engine = MatchEngine(criteria: criteria)
        let tracks = trackList
        matchTask = Task {
            do {
                try await Task.sleep(for: delay)
                let found = try await engine.findDuplicates(in: tracks) { fraction in
                    Task { @MainActor in self.showMatchProgress(fraction, for: id) }
                }
                finishMatching(found, for: id)
            } catch {
                // Only cancellation reaches here: a newer run has taken over.
            }
        }
    }

    private func showMatchProgress(_ fraction: Double, for id: UUID) {
        guard id == matchID, case .matching = matchState else { return }
        matchState = .matching(progress: fraction)
    }

    /// Ignores results from a run that a newer one replaced after it finished.
    private func finishMatching(_ found: [DuplicateGroup], for id: UUID) {
        guard id == matchID else { return }
        groups = found
        matchState = .finished
        // A copy that's no longer in any group can't be seen, so it mustn't stay marked.
        let grouped = Set(found.flatMap(\.trackIDs))
        if !marked.isSubset(of: grouped) {
            marked.formIntersection(grouped)
            marksRevision += 1
        }
        arrange()
    }

    private func arrange() {
        shownGroups = GroupArrangement.arrange(groups, tracks: tracks, index: searchIndex, filter: filter, order: order)
        revision += 1
    }

    // MARK: - Marks

    func setMarked(_ ids: some Sequence<Track.ID>, _ isMarked: Bool) {
        let before = marked
        if isMarked { marked.formUnion(ids) } else { marked.subtract(ids) }
        if marked != before { marksRevision += 1 }
    }

    func toggleMark(_ id: Track.ID) {
        setMarked([id], !marked.contains(id))
    }

    func isEveryCopyMarked(in group: DuplicateGroup) -> Bool {
        group.trackIDs.allSatisfy(marked.contains)
    }

    var markedSize: Int64 {
        marked.reduce(0) { $0 + (tracks[$1]?.fileSize ?? 0) }
    }

    var shownCopyCount: Int {
        shownGroups.reduce(0) { $0 + $1.trackIDs.count }
    }

    // MARK: - Columns

    func toggleColumn(_ column: TrackColumn) {
        if let index = columns.firstIndex(of: column) {
            columns.remove(at: index)
        } else {
            columns.append(column)
        }
    }

    func restoreDefaultColumns() {
        columns = TrackColumn.defaults
        columnWidths = [:]
    }
}

/// Match settings and the column layout, kept in user defaults.
struct ResultsSettings {
    let defaults: UserDefaults

    private enum Key {
        static let criteria = "matchCriteria"
        static let columns = "resultColumns"
        static let columnWidths = "resultColumnWidths"
    }

    /// Falls back to the standard settings if the saved ones can't be read,
    /// for example after the settings format changes.
    var criteria: MatchCriteria {
        get {
            defaults.data(forKey: Key.criteria).flatMap { try? JSONDecoder().decode(MatchCriteria.self, from: $0) } ?? .standard
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.criteria)
        }
    }

    var columns: [TrackColumn] {
        get {
            guard let ids = defaults.stringArray(forKey: Key.columns) else { return TrackColumn.defaults }
            return ids.compactMap(TrackColumn.init(id:))
        }
        nonmutating set {
            defaults.set(newValue.map(\.id), forKey: Key.columns)
        }
    }

    var columnWidths: [String: Double] {
        get { defaults.dictionary(forKey: Key.columnWidths) as? [String: Double] ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: Key.columnWidths) }
    }
}
