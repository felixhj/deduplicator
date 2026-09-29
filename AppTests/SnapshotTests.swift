import AppKit
import DedupCore
import DedupScanner
import SwiftUI
import Testing
@testable import Deduplicator

/// Renders the results screen to PNG files for a person to look at. Runs only
/// when SNAPSHOT_DIR is set, for example with
/// `TEST_RUNNER_SNAPSHOT_DIR=/tmp/shots xcodebuild test …`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] != nil))
struct SnapshotTests {
    let storage = TestDefaults()
    let folder = TemporaryFolder()

    /// A copy in the player, paused partway through, with its waveform drawn:
    /// a swell, a break and a louder second half.
    @Test(arguments: [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)])
    func resultsScreen(name: String, appearance: NSAppearance.Name) async throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"]!, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let tracks = try Fixtures.playableLibrary(in: folder.url, seconds: 12) { time in
            let beat = 0.55 + 0.45 * abs(sin(time * .pi * 2))
            switch time {
            case ..<3: return time / 3 * 0.5 * beat
            case ..<4.5: return 0.08
            default: return (0.6 + 0.02 * (time - 4.5)) * beat
            }
        }
        let library = LibraryModel(
            defaults: storage.defaults, cacheURL: nil, waveformFolder: nil, removalLog: nil,
            fileMover: TestMover(bin: folder.url.appending(path: "Bin", directoryHint: .isDirectory))
        )
        library.results.load(tracks)
        try await waitForMatching(library.results)
        library.results.setMarked([2], true)
        _ = await library.removal.removeMarked(to: .moveToBin)
        library.results.setMarked([4], true)
        library.player.select(tracks[1], copies: Array(tracks[0...1]))
        library.player.seek(to: 5)
        try await waitUntil("the waveform") { !library.player.isDrawingWaveform }
        let summary = ScanSummary(result: ScanResult(tracks: tracks), elapsed: .seconds(2))

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1500, height: 560), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        let host = NSHostingView(rootView: ResultsView(summary: summary).environment(library))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(800))
        host.layoutSubtreeIfNeeded()

        try save(host, as: "results-\(name)", in: directory)
        window.close()
    }

    @Test(arguments: [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)])
    func matchSettings(name: String, appearance: NSAppearance.Name) async throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"]!, directoryHint: .isDirectory)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 1500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        let host = NSHostingView(rootView: MatchSettingsView(criteria: .constant(.djLibrary), presets: .constant([])))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        try save(host, as: "settings-\(name)", in: directory)
        window.close()
    }

    /// Two copies marked in a group the filter hides, one of which leaves
    /// that group with every copy marked, going to a folder.
    @Test(arguments: [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)])
    func removeSheet(name: String, appearance: NSAppearance.Name) async throws {
        let library = LibraryModel(defaults: storage.defaults, cacheURL: nil, waveformFolder: nil, removalLog: nil)
        library.addFolders([URL(filePath: "/Music", directoryHint: .isDirectory)])
        library.results.load(Fixtures.library)
        try await waitForMatching(library.results)
        library.results.setMarked([2, 3, 4], true)
        library.results.filter.text = "strings"
        storage.defaults.set("folder", forKey: RemovalDestination.key)
        storage.defaults.set("/Volumes/Backup/Dupes", forKey: RemovalDestination.folderKey)
        try await snapshot(RemoveSheet().environment(library).defaultAppStorage(storage.defaults), as: "remove-\(name)", appearance: appearance)
    }

    @Test func autoSelectSheet() async throws {
        let library = LibraryModel(defaults: storage.defaults, cacheURL: nil, waveformFolder: nil, removalLog: nil)
        library.results.load(Fixtures.library)
        try await waitForMatching(library.results)
        library.results.keeperRules = [.pathDoesNotContain("Downloads"), .preferLossless, .higherBitrate, .preferFormat(.aiff)]
        try await snapshot(AutoSelectSheet().environment(library), as: "auto-select", appearance: .darkAqua)
    }

    @Test(arguments: [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)])
    func copyTagsSheet(name: String, appearance: NSAppearance.Name) async throws {
        let tracks = try Fixtures.taggedPair(in: folder.url)
        let library = LibraryModel(defaults: storage.defaults, cacheURL: nil, waveformFolder: nil, removalLog: nil, tagLog: nil)
        library.results.load(tracks)
        try await waitForMatching(library.results)
        library.results.setMarked([1], true)
        try await snapshot(CopyTagsSheet(request: TagCopyRequest(source: 1)).environment(library), as: "copy-tags-\(name)", appearance: appearance)
    }

    @Test func help() async throws {
        try await snapshot(HelpView(), as: "help", appearance: .aqua)
    }

    @Test func keyboardShortcuts() async throws {
        try await snapshot(ShortcutsView(), as: "shortcuts", appearance: .darkAqua)
    }

    @Test func matchSettingsWithASavedPreset() async throws {
        var criteria = MatchCriteria.standard
        criteria.durationTolerance = 9
        let view = MatchSettingsView(criteria: .constant(criteria), presets: .constant([SavedPreset(name: "Nine seconds", criteria: criteria)]))
        try await snapshot(view.frame(width: 340, height: 220), as: "saved-preset", appearance: .aqua)
    }

    @Test func removalReport() async throws {
        let failure = RemovalFailure(
            trackID: 1, source: URL(filePath: "/Music/House/Strings of Life.mp3"),
            message: "“Strings of Life.mp3” couldn’t be moved because you don’t have permission to access “House”."
        )
        let report = RemovalModel.Report(summary: "Moved 11 files to the Bin. 1 file couldn't be moved.", failures: [failure], isComplete: false)
        try await snapshot(RemovalReportView(report: report) {}.padding(20).frame(width: 560), as: "removal-report", appearance: .aqua)
    }

    @Test func settings() async throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"]!, directoryHint: .isDirectory)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SettingsView().defaultAppStorage(storage.defaults))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        try save(host, as: "app-settings", in: directory)
        window.close()
    }

    /// The whole window, title bar and toolbar included.
    @Test func mainWindow() async throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"]!, directoryHint: .isDirectory)
        let library = LibraryModel(defaults: storage.defaults, cacheURL: nil, waveformFolder: nil, removalLog: nil)
        library.addFolders([URL(filePath: "/Music", directoryHint: .isDirectory)])
        library.results.load(Fixtures.library)
        try await waitForMatching(library.results)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1500, height: 600), styleMask: [.titled, .resizable, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ResultsView(summary: ScanSummary(result: ScanResult(tracks: Fixtures.library), elapsed: .seconds(2))).environment(library))
        host.sceneBridgingOptions = .all
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(800))
        try save(try #require(window.contentView?.superview), as: "window", in: directory)
        window.close()
    }

    /// Renders a sheet's content on its own.
    private func snapshot(_ view: some View, as name: String, appearance: NSAppearance.Name) async throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"]!, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        host.setFrameSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        try save(host, as: name, in: directory)
        window.close()
    }

    private func save(_ view: NSView, as name: String, in directory: URL) throws {
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appending(path: "\(name).png"))
    }
}
