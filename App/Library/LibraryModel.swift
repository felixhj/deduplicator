import DedupCore
import DedupScanner
import Foundation
import Observation

/// The folders to scan and the tracks found in them.
@MainActor
@Observable
final class LibraryModel {
    enum ScanState {
        case idle
        case scanning(ScanProgress)
        case finished(ScanSummary)
        case failed(String)
    }

    private(set) var folders: [URL]
    private(set) var state: ScanState = .idle
    private(set) var issues: [ScanIssue] = []
    /// Duplicates among the tracks from the last scan.
    let results: ResultsModel
    /// Plays copies from the results.
    let player: PlayerModel
    /// Removes marked copies and undoes removals.
    let removal: RemovalModel
    /// Writes tags copied between copies.
    let tagWriter: TagWriter
    /// Set to show the folder picker, for example from the Add Folder command.
    var isChoosingFolders = false

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanID = UUID()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cacheURL: URL?
    private static let foldersKey = "scanFolders"

    /// `cacheURL` is where scans keep their cache, `waveformFolder` where the
    /// player keeps waveforms, and `removalLog` and `tagLog` where removals
    /// and tag writes are logged; nil turns any of them off. `fileMover`
    /// moves removed files.
    init(
        defaults: UserDefaults = .standard,
        cacheURL: URL? = AppFolders.scanCache,
        waveformFolder: URL? = AppFolders.waveforms,
        removalLog: URL? = AppFolders.removalLog,
        tagLog: URL? = AppFolders.tagEditLog,
        fileMover: any FileMover = LocalFileMover()
    ) {
        self.defaults = defaults
        self.cacheURL = cacheURL
        results = ResultsModel(defaults: defaults)
        player = PlayerModel(defaults: defaults, waveforms: waveformFolder.map { WaveformCache(folder: $0) })
        removal = RemovalModel(results: results, player: player, logURL: removalLog, mover: fileMover)
        tagWriter = TagWriter(results: results, player: player, logURL: tagLog)
        folders = (defaults.stringArray(forKey: Self.foldersKey) ?? [])
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    var isScanning: Bool {
        if case .scanning = state { true } else { false }
    }

    var canScan: Bool { !isScanning && !folders.isEmpty && !removal.isBusy && !isShowingSheet }

    /// Removing waits for matching to settle, since it can drop marks.
    var canRemove: Bool {
        !isScanning && !removal.isBusy && !isShowingSheet && results.matchState == .finished && !results.marked.isEmpty
    }

    var canAutoSelect: Bool {
        !isScanning && !removal.isBusy && !isShowingSheet && results.matchState == .finished && !results.shownGroups.isEmpty
    }

    var canUndoRemoval: Bool { removal.canUndo && !isScanning && !isShowingSheet }

    /// Copying tags starts from one selected copy.
    var canCopyTags: Bool {
        !isScanning && !removal.isBusy && !isShowingSheet && results.selection.count == 1
    }

    /// Menu commands still work while a sheet is up, and a window shows one
    /// sheet at a time, so commands that open one, or change what one shows, wait.
    var isShowingSheet: Bool {
        removal.isConfirmingRemoval || removal.isUndoing || results.isAutoSelecting || results.tagCopyRequest != nil
    }

    /// Adds folders that aren't in the list yet, including repeats within `urls`.
    func addFolders(_ urls: [URL]) {
        var known = Set(folders.map(Self.folderKey))
        let new = urls
            .map { URL(filePath: $0.path(percentEncoded: false), directoryHint: .isDirectory).standardizedFileURL }
            .filter { known.insert(Self.folderKey($0)).inserted }
        guard !new.isEmpty else { return }
        folders += new
        saveFolders()
    }

    /// Compares folders by path, whether or not the URL ends in a slash.
    private static func folderKey(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    func removeFolders(_ urls: Set<URL>) {
        folders.removeAll { urls.contains($0) }
        saveFolders()
    }

    func scan() {
        guard canScan else { return }
        // The results, player included, make way for the scan's progress.
        player.unload()
        let id = UUID()
        scanID = id
        let previous = state
        state = .scanning(ScanProgress(phase: .finding, found: 0, completed: 0))
        let scanner = LibraryScanner(cacheURL: cacheURL)
        let folders = folders
        scanTask = Task {
            let started = ContinuousClock.now
            do {
                let result = try await scanner.scan(folders) { progress in
                    Task { @MainActor in self.show(progress, for: id) }
                }
                finish(result, elapsed: ContinuousClock.now - started)
            } catch is CancellationError {
                state = previous
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    /// Progress arrives on separate tasks, so late reports from a scan that
    /// has finished, or from an earlier scan, are dropped.
    private func show(_ progress: ScanProgress, for id: UUID) {
        guard id == scanID, isScanning else { return }
        state = .scanning(progress)
    }

    private func finish(_ result: ScanResult, elapsed: Duration) {
        results.load(result.tracks)
        issues = result.issues
        state = .finished(ScanSummary(result: result, elapsed: elapsed))
    }

    private func saveFolders() {
        defaults.set(folders.map { $0.path(percentEncoded: false) }, forKey: Self.foldersKey)
    }
}

/// What the last scan found, for the status view.
struct ScanSummary {
    var trackCount: Int
    var cachedCount: Int
    var issueCount: Int
    /// Formats in a fixed order, with how many tracks of each were found.
    var formatCounts: [(format: AudioFormat, count: Int)]
    var elapsed: Duration

    init(result: ScanResult, elapsed: Duration) {
        trackCount = result.tracks.count
        cachedCount = result.cachedCount
        issueCount = result.issues.count
        let counts = Dictionary(grouping: result.tracks, by: \.audio.format).mapValues(\.count)
        formatCounts = AudioFormat.allCases.compactMap { format in counts[format].map { (format, $0) } }
        self.elapsed = elapsed
    }
}
