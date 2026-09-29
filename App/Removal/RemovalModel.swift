import DedupCore
import Foundation
import Observation

/// Where removed files go, as chosen in Settings or the confirm sheet. Both
/// keep it in user defaults under `key`, and the folder under `folderKey`.
enum RemovalDestination: String {
    case bin, folder

    static let key = "removalDestination"
    static let folderKey = "removalFolder"

    /// The removal mode, or nil when a folder is wanted but none is chosen.
    func mode(folderPath: String) -> RemovalMode? {
        switch self {
        case .bin: .moveToBin
        case .folder: folderPath.isEmpty ? nil : .moveToFolder(URL(filePath: folderPath, directoryHint: .isDirectory))
        }
    }
}

/// Removes the marked copies, and undoes removals. Files are moved off the
/// main actor, every removal is written to the log, and the last one that
/// hasn't been undone can be, even after the app is reopened.
@MainActor
@Observable
final class RemovalModel {
    enum Activity: Equatable {
        case idle
        case removing(done: Int, total: Int)
        case undoing(done: Int, total: Int)
    }

    /// What a removal or undo did.
    struct Report: Equatable {
        var summary: String
        var failures: [RemovalFailure]
        /// Every file went where it should, and the log was saved.
        var isComplete = true
    }

    private(set) var activity: Activity = .idle
    private(set) var log: RemovalLog
    /// Says what the last removal did, until it's undone, for the status bar.
    private(set) var lastRemoval: String?
    /// Why the log couldn't be read or saved, if it couldn't.
    private(set) var logProblem: String?
    /// Set to show the confirm sheet, for example from the File menu.
    var isConfirmingRemoval = false
    /// Set to show the undo sheet, which undoes the last removal as it opens.
    var isUndoing = false

    @ObservationIgnored private let results: ResultsModel
    @ObservationIgnored private let player: PlayerModel
    @ObservationIgnored private let executor: RemovalExecutor
    @ObservationIgnored private let logURL: URL?
    @ObservationIgnored private var removal: Task<RemovalOperation, Never>?
    @ObservationIgnored private var workID = UUID()
    /// The tracks each removal in this session took out of the results, so
    /// undoing it can put them back without a scan. Only while the scan they
    /// came from is still loaded, since track IDs belong to one scan.
    @ObservationIgnored private var removedTracks: [RemovalOperation.ID: (generation: Int, tracks: [Track])] = [:]

    /// `logURL` is where the log is kept; nil keeps it in memory only.
    init(results: ResultsModel, player: PlayerModel, logURL: URL?, mover: any FileMover) {
        self.results = results
        self.player = player
        self.logURL = logURL
        executor = RemovalExecutor(mover: mover)
        (log, logProblem) = loadLog(from: logURL, empty: RemovalLog(), reading: RemovalLog.load(from:))
    }

    var isBusy: Bool { activity != .idle }

    /// The removal that undoing would put back.
    var undoable: RemovalOperation? { log.lastUndoable }

    var canUndo: Bool { !isBusy && undoable != nil }

    // MARK: - Removing

    /// Moves the marked copies to where `mode` says. The moved copies leave
    /// the results, and the player if it has one of them.
    func removeMarked(to mode: RemovalMode) async -> Report? {
        let tracks = results.marked.compactMap { results.tracks[$0] }.sorted { $0.id < $1.id }
        guard !isBusy, !tracks.isEmpty else { return nil }
        let plan = RemovalPlanner.plan(tracks, mode: mode)
        let generation = results.generation
        let id = UUID()
        workID = id
        activity = .removing(done: 0, total: plan.count)
        let executor = executor
        let progress = progressReporter(for: id)
        let task = Task.detached { executor.execute(plan, mode: mode, progress: progress) }
        removal = task
        let operation = await task.value
        removal = nil
        activity = .idle

        let moved = Set(operation.records.map(\.trackID))
        if results.generation == generation {
            results.remove(moved)
            removedTracks = removedTracks.filter { $0.value.generation == generation }
            removedTracks[operation.id] = (generation, tracks.filter { moved.contains($0.id) })
        }
        if let current = player.track, moved.contains(current.id) {
            player.unload()
        }
        if !operation.records.isEmpty || !operation.failures.isEmpty {
            log.append(operation)
            saveLog()
        }
        let summary = Self.summary(of: operation, planned: plan.count)
        lastRemoval = operation.records.isEmpty ? nil : summary
        return report(summary, failures: operation.failures, finished: operation.records.count + operation.failures.count == plan.count)
    }

    /// Stops a removal before its next file. What was moved stays moved, and
    /// can be undone.
    func stop() {
        removal?.cancel()
    }

    // MARK: - Undoing

    /// Puts the files of the last removal back where they were. Their copies
    /// return to the results if the scan they came from is still loaded.
    func undoLast() async -> Report? {
        guard !isBusy, let operation = undoable else { return nil }
        let id = UUID()
        workID = id
        activity = .undoing(done: 0, total: operation.records.count)
        let executor = executor
        let progress = progressReporter(for: id)
        let result = await Task.detached { executor.undo(operation, progress: progress) }.value
        activity = .idle

        log.markUndone(operation.id, failures: result.failures)
        saveLog()
        lastRemoval = nil
        let restored = Set(result.restored.map(\.trackID))
        var summary = Self.summary(restored: restored.count, failed: result.failures.count)
        if let removed = removedTracks.removeValue(forKey: operation.id), removed.generation == results.generation {
            results.restore(removed.tracks.filter { restored.contains($0.id) })
        } else if !restored.isEmpty {
            summary += restored.count == 1 ? " Scan again to see it in the results." : " Scan again to see them in the results."
        }
        return report(summary, failures: result.failures, finished: true)
    }

    // MARK: - Reporting

    /// Passes progress from the thread moving files to the main actor.
    private func progressReporter(for id: UUID) -> @Sendable (Int) -> Void {
        { [weak self] done in
            Task { @MainActor in self?.showProgress(done, for: id) }
        }
    }

    private func showProgress(_ done: Int, for id: UUID) {
        guard id == workID else { return }
        switch activity {
        case .removing(_, let total): activity = .removing(done: done, total: total)
        case .undoing(_, let total): activity = .undoing(done: done, total: total)
        case .idle: break
        }
    }

    /// "Moved 12 files to the Bin.", and what went wrong, if anything did.
    static func summary(of operation: RemovalOperation, planned: Int) -> String {
        let moved = operation.records.count
        let failed = operation.failures.count
        let place = switch operation.mode {
        case .moveToBin: "the Bin"
        case .moveToFolder(let folder): "“\(folder.lastPathComponent)”"
        }
        var summary: String
        if moved + failed < planned {
            summary = "Stopped after moving \(moved.formatted()) of \(files(planned)) to \(place)."
        } else if moved == 0 {
            return failed == 1 ? "The file couldn't be moved." : "None of the \(failed.formatted()) files could be moved."
        } else {
            summary = "Moved \(files(moved)) to \(place)."
        }
        if failed > 0 {
            summary += " \(files(failed)) couldn't be moved."
        }
        return summary
    }

    /// "Put back 12 files.", and how many couldn't be.
    static func summary(restored: Int, failed: Int) -> String {
        switch (restored, failed) {
        case (_, 0): "Put back \(files(restored))."
        case (0, 1): "The file couldn't be put back."
        case (0, _): "None of the \(failed.formatted()) files could be put back."
        default: "Put back \(files(restored)). \(files(failed)) couldn't be put back."
        }
    }

    /// "1 file", "12 files".
    static func files(_ count: Int) -> String {
        "\(count.formatted()) \(count == 1 ? "file" : "files")"
    }

    /// A problem with the log is told once, with the next report.
    private func report(_ summary: String, failures: [RemovalFailure], finished: Bool) -> Report {
        defer { logProblem = nil }
        return Report(
            summary: [summary, logProblem].compactMap { $0 }.joined(separator: " "),
            failures: failures,
            isComplete: finished && failures.isEmpty && logProblem == nil
        )
    }

    // MARK: - Log

    private func saveLog() {
        guard let logURL else { return }
        do {
            try log.save(to: logURL)
        } catch {
            logProblem = "The removal log couldn't be saved. \(error.localizedDescription)"
        }
    }
}
