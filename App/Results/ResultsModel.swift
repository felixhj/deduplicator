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
    /// Counts the scans loaded. Track IDs belong to one scan, so anything
    /// holding IDs can tell when a new scan has replaced its own.
    private(set) var generation = 0

    var criteria: MatchCriteria {
        didSet {
            guard criteria != oldValue else { return }
            settings.criteria = criteria
            match(after: .milliseconds(300))
        }
    }

    /// The text isn't kept between launches; the minimum confidence is.
    var filter = ResultFilter() {
        didSet {
            guard filter != oldValue else { return }
            if filter.minimumConfidence != oldValue.minimumConfidence { settings.minimumConfidence = filter.minimumConfidence }
            arrange()
        }
    }

    var order: GroupOrder = .confidence {
        didSet {
            guard order != oldValue else { return }
            settings.order = order
            arrange()
        }
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

    /// The rules auto-select keeps a copy by, in order.
    var keeperRules: [KeeperRule] {
        didSet { if keeperRules != oldValue { settings.keeperRules = keeperRules } }
    }

    /// Match settings the user saved as presets.
    var savedPresets: [SavedPreset] {
        didSet { if savedPresets != oldValue { settings.savedPresets = savedPresets } }
    }

    /// Set to show the auto-select sheet, for example from the Edit menu.
    var isAutoSelecting = false

    /// Set to show the Copy Tags sheet, copying from the copy it names.
    var tagCopyRequest: TagCopyRequest?

    /// Goes up to move the keyboard focus to the filter, as Find does.
    var filterFocusRequests = 0

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
        keeperRules = settings.keeperRules
        savedPresets = settings.savedPresets
        order = settings.order
        filter.minimumConfidence = settings.minimumConfidence
    }

    /// Takes the tracks from a new scan. Marks are cleared, because track IDs
    /// belong to one scan.
    func load(_ tracks: [Track]) {
        generation += 1
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

    func unmarkAll() {
        setMarked(marked, false)
    }

    // MARK: - Auto-select

    /// What auto-select would do to the groups shown: keep one copy of each,
    /// chosen by `keeperRules`, and mark the rest.
    func keeperChoices() -> [KeeperChoice] {
        KeeperSelector(rules: keeperRules).choices(for: shownGroups, tracks: tracks)
    }

    /// Marks every copy but the keeper in each group, replacing any marks
    /// made by hand in those groups.
    func apply(_ choices: [KeeperChoice]) {
        let before = marked
        marked.subtract(choices.map(\.keeper))
        marked.formUnion(choices.flatMap(\.others))
        if marked != before { marksRevision += 1 }
    }

    // MARK: - Removing and restoring

    /// Takes removed copies out of the results. Their groups lose them, and
    /// a group left with one copy goes. Matching runs without them from now
    /// on, so changing the settings doesn't bring them back.
    func remove(_ ids: Set<Track.ID>) {
        guard !ids.isEmpty else { return }
        trackList.removeAll { ids.contains($0.id) }
        for id in ids { tracks[id] = nil }
        searchIndex.remove(ids)
        if !marked.isDisjoint(with: ids) {
            marked.subtract(ids)
            marksRevision += 1
        }
        selection.subtract(ids)
        groups = groups.compactMap { group in
            var group = group
            group.trackIDs.removeAll(where: ids.contains)
            return group.trackIDs.count > 1 ? group : nil
        }
        arrange()
        if case .matching = matchState {
            // The run under way still has them, so it starts again without.
            match()
        }
    }

    /// Shows a copy's new values, as after its tags were written. The groups
    /// stay as they are; matching uses the new values the next time it runs.
    func update(_ track: Track) {
        guard tracks[track.id] != nil else { return }
        tracks[track.id] = track
        if let index = trackList.firstIndex(where: { $0.id == track.id }) {
            trackList[index] = track
        }
        searchIndex.remove([track.id])
        searchIndex.add([track])
        let newKeys = Set(track.tags.keys).subtracting(tagKeys)
        if !newKeys.isEmpty { tagKeys = (tagKeys + newKeys).sorted() }
        arrange()
    }

    /// The copies in the group holding `id`, in group order.
    func copies(inGroupOf id: Track.ID) -> [Track] {
        groups.first { $0.trackIDs.contains(id) }?.trackIDs.compactMap { tracks[$0] } ?? []
    }

    /// Puts back copies whose removal was undone, then finds duplicates again.
    func restore(_ restored: [Track]) {
        guard !restored.isEmpty else { return }
        // Matching lists copies in scan order, which is ID order.
        trackList = (trackList + restored).sorted { $0.id < $1.id }
        for track in restored { tracks[track.id] = track }
        searchIndex.add(restored)
        match()
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

/// Which copy to copy tags from, for the Copy Tags sheet.
struct TagCopyRequest: Identifiable, Equatable {
    var source: Track.ID
    var id: Track.ID { source }
}

/// Match settings and the column layout, kept in user defaults.
struct ResultsSettings {
    let defaults: UserDefaults

    private enum Key {
        static let criteria = "matchCriteria"
        static let columns = "resultColumns"
        static let columnWidths = "resultColumnWidths"
        static let keeperRules = "keeperRules"
        static let savedPresets = "matchPresets"
        static let order = "groupOrder"
        static let minimumConfidence = "minimumConfidence"
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

    var keeperRules: [KeeperRule] {
        get {
            defaults.data(forKey: Key.keeperRules).flatMap { try? JSONDecoder().decode([KeeperRule].self, from: $0) }
                ?? KeeperSelector.defaultRules
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.keeperRules)
        }
    }

    var savedPresets: [SavedPreset] {
        get {
            defaults.data(forKey: Key.savedPresets).flatMap { try? JSONDecoder().decode([SavedPreset].self, from: $0) } ?? []
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.savedPresets)
        }
    }

    /// Saved as "confidence", "copies", or "column:<id>:ascending" or ":descending".
    var order: GroupOrder {
        get {
            let parts = (defaults.string(forKey: Key.order) ?? "").split(separator: ":", maxSplits: 1).map(String.init)
            switch parts.first {
            case "copies": return .copies
            case "column" where parts.count == 2:
                let rest = parts[1]
                guard let colon = rest.lastIndex(of: ":"), let column = TrackColumn(id: String(rest[..<colon])) else { return .confidence }
                return .column(column, ascending: rest[rest.index(after: colon)...] == "ascending")
            default: return .confidence
            }
        }
        nonmutating set {
            let value = switch newValue {
            case .confidence: "confidence"
            case .copies: "copies"
            case .column(let column, let ascending): "column:\(column.id):\(ascending ? "ascending" : "descending")"
            }
            defaults.set(value, forKey: Key.order)
        }
    }

    var minimumConfidence: Double {
        get { defaults.double(forKey: Key.minimumConfidence) }
        nonmutating set { defaults.set(newValue, forKey: Key.minimumConfidence) }
    }
}
