import AppKit
import SwiftUI
import Testing
@testable import Deduplicator

/// The main window never lays its columns out wider than itself, however
/// narrow it's made or wherever the sidebar's divider is dragged.
@MainActor
struct WindowLayoutTests {
    let storage = TestDefaults()
    let folder = TemporaryFolder()

    /// The window as the app makes it, showing the results of a real scan.
    func makeWindow(showsMatchSettings: Bool = true) async throws -> NSWindow {
        storage.defaults.set(showsMatchSettings, forKey: "showsMatchSettings")
        _ = try Fixtures.playableLibrary(in: folder.url, seconds: 0.2)
        let library = LibraryModel(defaults: storage.defaults, cacheURL: nil, waveformFolder: nil, removalLog: nil, tagLog: nil)
        library.addFolders([folder.url])
        library.scan()
        try await waitUntil("the scan") { library.hasResults }
        try await waitForMatching(library.results)
        let updates = UpdateChecker(currentVersion: "1.0.0", defaults: storage.defaults) { throw UpdateChecker.Failure.status(404) }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 600),
            styleMask: [.titled, .resizable, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let content = ContentView().environment(library).environment(updates).defaultAppStorage(storage.defaults).mainWindowSizing()
        window.contentViewController = NSHostingController(rootView: content)
        try await settle(window)
        return window
    }

    func settle(_ window: NSWindow) async throws {
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    /// The outermost split view, which holds every column.
    func columns(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView { return split }
        return view.subviews.lazy.compactMap(columns(in:)).first
    }

    func expectColumnsInside(_ window: NSWindow, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let content = try #require(window.contentView, sourceLocation: sourceLocation)
        let split = try #require(columns(in: content), sourceLocation: sourceLocation)
        let frame = split.convert(split.bounds, to: nil)
        let width = window.contentView?.frame.width ?? 0
        #expect(frame.minX >= 0 && frame.maxX <= width + 0.5, "Columns at \(frame.minX)…\(frame.maxX) in a window \(width) wide", sourceLocation: sourceLocation)
    }

    @Test(arguments: [true, false])
    func narrowingNeverCutsTheColumnsOff(showsMatchSettings: Bool) async throws {
        let window = try await makeWindow(showsMatchSettings: showsMatchSettings)
        defer { window.close() }
        for width in [1100.0, 900, 700, 500] {
            window.setContentSize(NSSize(width: width, height: 600))
            try await settle(window)
            try expectColumnsInside(window)
        }
    }

    @Test func draggingTheSidebarNeverCutsTheColumnsOff() async throws {
        let window = try await makeWindow()
        defer { window.close() }
        window.setContentSize(NSSize(width: 500, height: 600))
        try await settle(window)
        let content = try #require(window.contentView)
        let split = try #require(columns(in: content))
        split.setPosition(900, ofDividerAt: 0)
        try await settle(window)
        try expectColumnsInside(window)
    }

    @Test func showingTheMatchSettingsInANarrowWindowKeepsThemInside() async throws {
        // A real defaults suite, since the view only hears about changes through KVO.
        let suite = "WindowLayoutTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "showsMatchSettings")
        let library = LibraryModel(defaults: storage.defaults, cacheURL: nil, waveformFolder: nil, removalLog: nil, tagLog: nil)
        _ = try Fixtures.playableLibrary(in: folder.url, seconds: 0.2)
        library.addFolders([folder.url])
        library.scan()
        try await waitUntil("the scan") { library.hasResults }
        let updates = UpdateChecker(currentVersion: "1.0.0", defaults: storage.defaults) { throw UpdateChecker.Failure.status(404) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 600), styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentViewController = NSHostingController(rootView: ContentView().environment(library).environment(updates).defaultAppStorage(defaults).mainWindowSizing())
        window.setContentSize(NSSize(width: 500, height: 600))
        try await settle(window)
        try expectColumnsInside(window)

        defaults.set(true, forKey: "showsMatchSettings")
        try await settle(window)
        try await Task.sleep(for: .milliseconds(500))
        try expectColumnsInside(window)
        print("After showing the settings: window \(window.contentView?.frame.width ?? 0) wide")
    }

    /// The player bar makes way, so the table's column needn't keep the
    /// window wide.
    @Test func theWindowCanGetFairlyNarrow() async throws {
        let window = try await makeWindow(showsMatchSettings: false)
        defer { window.close() }
        window.setContentSize(NSSize(width: 500, height: 600))
        try await settle(window)
        #expect((window.contentView?.frame.width ?? .infinity) <= 800)
    }
}
