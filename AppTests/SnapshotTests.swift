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

    @Test(arguments: [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)])
    func resultsScreen(name: String, appearance: NSAppearance.Name) async throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"]!, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let library = LibraryModel(defaults: storage.defaults)
        library.results.load(Fixtures.library)
        library.results.setMarked([2], true)
        try await waitForMatching(library.results)
        let summary = ScanSummary(result: ScanResult(tracks: Fixtures.library), elapsed: .seconds(2))

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
        let host = NSHostingView(rootView: MatchSettingsView(criteria: .constant(.djLibrary)))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        try save(host, as: "settings-\(name)", in: directory)
        window.close()
    }

    /// The whole window, title bar and toolbar included.
    @Test func mainWindow() async throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"]!, directoryHint: .isDirectory)
        let library = LibraryModel(defaults: storage.defaults)
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

    private func save(_ view: NSView, as name: String, in directory: URL) throws {
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appending(path: "\(name).png"))
    }
}
