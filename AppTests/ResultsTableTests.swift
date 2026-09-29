import AppKit
import DedupCore
import Foundation
import Testing
@testable import Deduplicator

/// Drives the real table view and its controller, without a window on screen.
@MainActor
struct ResultsTableTests {
    let storage = TestDefaults()
    let folder = TemporaryFolder()

    /// The fixture library in a table. Its files don't exist unless `playable`.
    func makeTable(playable: Bool = false) async throws -> (ResultsModel, ResultsTableController) {
        let model = ResultsModel(defaults: storage.defaults)
        model.load(playable ? try Fixtures.playableLibrary(in: folder.url) : Fixtures.library)
        try await waitForMatching(model)
        let table = ResultsTableController(model: model, player: PlayerModel(defaults: storage.defaults))
        table.update()
        return (model, table)
    }

    /// Puts the table in an off-screen window so its rows get views.
    func realise(_ table: ResultsTableController) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = table.scrollView
        window.display()
        return window
    }

    var columnIDs: (ResultsTableController) -> [String] {
        { $0.tableView.tableColumns.map(\.identifier.rawValue) }
    }

    @Test func showsAHeaderAboveEachGroupsCopies() async throws {
        let (_, table) = try await makeTable()
        #expect(table.tableView.numberOfRows == 7)
        #expect(table.item(atRow: 0) is GroupItem)
        #expect((1...3).map { (table.item(atRow: $0) as? CopyItem)?.track.id } == [0, 1, 2])
        #expect(table.item(atRow: 4) is GroupItem)
        #expect((table.item(atRow: 0) as? GroupItem)?.detail == "3 copies · 100% · Same title · Same artist · Duration within tolerance")
        #expect((table.item(atRow: 0) as? GroupItem)?.title == "Derrick May – Strings of Life")
    }

    @Test func columnsFollowTheModel() async throws {
        let (model, table) = try await makeTable()
        #expect(columnIDs(table) == ["mark", "play"] + TrackColumn.defaults.map(\.id))
        model.toggleColumn(.tag("INITIALKEY"))
        table.update()
        #expect(columnIDs(table).last == "tag:INITIALKEY")
        model.columns = [.artist, .title]
        table.update()
        #expect(columnIDs(table) == ["mark", "play", "artist", "title"])
    }

    @Test func movingAColumnUpdatesTheModel() async throws {
        let (model, table) = try await makeTable()
        model.columns = [.title, .artist, .album]
        table.update()
        table.tableView.moveColumn(4, toColumn: 2)
        #expect(model.columns == [.album, .title, .artist])
    }

    @Test func tickBoxAndPlayColumnsStayFirst() async throws {
        let (_, table) = try await makeTable()
        let tableView = table.tableView
        #expect(!table.tableView(tableView, shouldReorderColumn: 1, toColumn: 3))
        #expect(!table.tableView(tableView, shouldReorderColumn: 3, toColumn: 1))
        #expect(!table.tableView(tableView, shouldReorderColumn: 0, toColumn: 2))
        #expect(table.tableView(tableView, shouldReorderColumn: 3, toColumn: 2))
    }

    @Test func clickingAHeaderOrdersByThatColumn() async throws {
        let (model, table) = try await makeTable()
        table.tableView.sortDescriptors = [NSSortDescriptor(key: "bitrate", ascending: true)]
        #expect(model.order == .column(.bitrate, ascending: true))
        model.order = .confidence
        table.update()
        #expect(table.tableView.sortDescriptors.isEmpty)
    }

    @Test func dMarksAndKKeepsTheSelectedCopies() async throws {
        let (model, table) = try await makeTable()
        table.tableView.selectRowIndexes([1, 2], byExtendingSelection: false)
        #expect(model.selection == [0, 1])
        table.tableView.keyDown(with: keyEvent("d"))
        #expect(model.marked == [0, 1])
        table.tableView.keyDown(with: keyEvent("k"))
        #expect(model.marked.isEmpty)
    }

    @Test func commandArrowsMoveBetweenGroups() async throws {
        let (_, table) = try await makeTable()
        let outline = table.tableView
        outline.selectRowIndexes([2], byExtendingSelection: false)
        outline.keyDown(with: keyEvent(downArrow, modifiers: .command, keyCode: 125))
        #expect(outline.selectedRow == 5)
        outline.keyDown(with: keyEvent(upArrow, modifiers: .command, keyCode: 126))
        #expect(outline.selectedRow == 1)
    }

    @Test func headersCantBeSelected() async throws {
        let (_, table) = try await makeTable()
        table.tableView.selectRowIndexes([0, 1], byExtendingSelection: false)
        #expect(table.selectedTrackIDs == [0])
    }

    @Test func collapsedGroupsStayCollapsedWhenReordered() async throws {
        let (model, table) = try await makeTable()
        table.setExpanded(try #require(table.item(atRow: 0) as? GroupItem), false)
        #expect(table.tableView.numberOfRows == 4)
        #expect((table.item(atRow: 1) as? GroupItem)?.copies.count == 2)
        model.order = .column(.title, ascending: false)
        table.update()
        let collapsed = (0..<table.tableView.numberOfRows).compactMap { table.item(atRow: $0) as? GroupItem }
            .filter { !table.isExpanded($0) }
        #expect(collapsed.map(\.group.trackIDs.count) == [3])
        #expect(table.tableView.numberOfRows == 4)
    }

    @Test func differencesBetweenCopiesAreFound() async throws {
        let (_, table) = try await makeTable()
        let group = try #require(table.item(atRow: 0) as? GroupItem)
        #expect(group.differs(0, in: .format) && group.differs(1, in: .format) && group.differs(2, in: .format))
        #expect(!group.differs(0, in: .comment) && group.differs(2, in: .comment))
        #expect(!group.differs(0, in: .artist))
        #expect(!group.differs(0, in: .path))
    }

    @Test func tickBoxesAndWarningsFollowMarks() async throws {
        let (model, table) = try await makeTable()
        let window = realise(table)
        defer { window.close() }
        let outline = table.tableView
        let markColumn = outline.column(withIdentifier: ResultsTableController.markColumnID)
        let tickBox = { (row: Int) in outline.view(atColumn: markColumn, row: row, makeIfNecessary: false) as? MarkCellView }
        let header = { (row: Int) in outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? GroupHeaderView }
        #expect(tickBox(5)?.isMarked == false)
        #expect(header(4)?.everyCopyMarked == false)

        model.setMarked([3, 4], true)
        table.update()
        #expect(tickBox(5)?.isMarked == true)
        #expect(tickBox(6)?.isMarked == true)
        #expect(header(4)?.everyCopyMarked == true)
        #expect(header(0)?.everyCopyMarked == false)
    }
}

extension ResultsTableTests {
    @Test func headerButtonAndClicksCollapseGroups() async throws {
        let (_, table) = try await makeTable()
        let window = realise(table)
        defer { window.close() }
        let outline = table.tableView
        // Showing every group reloads the table, so views are made on demand here.
        let header = { (row: Int) in outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? GroupHeaderView }

        let first = try #require(header(0))
        #expect(first.isExpanded)
        first.subviews.first?.subviews.compactMap { $0 as? NSButton }.first?.performClick(nil)
        #expect(outline.numberOfRows == 4)
        #expect(!first.isExpanded)

        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: .option, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        try #require(header(0)).mouseDown(with: click)
        #expect(outline.numberOfRows == 7, "Option-click expands every group")
        try #require(header(0)).mouseDown(with: click)
        #expect(outline.numberOfRows == 2, "and collapses every group")
    }

    @Test func rowMenuMarksKeepsAndNeedsASelection() async throws {
        let (model, table) = try await makeTable()
        let menu = try #require(table.tableView.menu)
        #expect(menu.items.map(\.title) == ["Mark for Removal", "Keep", "", "Copy Tags from This Copy…", "Show in Finder"])
        #expect(!table.validateMenuItem(menu.items[0]))

        table.tableView.selectRowIndexes([5, 6], byExtendingSelection: false)
        #expect(table.validateMenuItem(menu.items[0]))
        #expect(!table.validateMenuItem(menu.items[3]), "Copying tags starts from one copy")
        menu.performActionForItem(at: 0)
        #expect(model.marked == [3, 4])
        menu.performActionForItem(at: 1)
        #expect(model.marked.isEmpty)

        table.tableView.selectRowIndexes([6], byExtendingSelection: false)
        menu.performActionForItem(at: 3)
        #expect(model.tagCopyRequest == TagCopyRequest(source: 4))
    }

    @Test func headerMenuListsColumnsAndTags() async throws {
        let (model, table) = try await makeTable()
        let menu = NSMenu()
        table.menuNeedsUpdate(menu)
        let names = menu.items.map(\.title)
        #expect(names.prefix(TrackColumn.builtIn.count) == ArraySlice(TrackColumn.builtIn.map(\.name)))
        #expect(names.suffix(3) == ["Tags", "", "Restore Default Columns"])
        #expect(menu.items.first { $0.title == "Title" }?.state == .on)
        #expect(menu.items.first { $0.title == "Genre" }?.state == .off)

        let tags = try #require(menu.items.first { $0.title == "Tags" }?.submenu)
        #expect(tags.items.map(\.title) == ["INITIALKEY"])
        tags.performActionForItem(at: 0)
        #expect(model.columns.last == .tag("INITIALKEY"))
        menu.performActionForItem(at: menu.items.count - 1)
        #expect(model.columns == TrackColumn.defaults)
    }

    @Test func resizingAColumnIsRemembered() async throws {
        let (model, table) = try await makeTable()
        let title = try #require(table.tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("title")))
        title.width = 333
        #expect(model.columnWidths["title"] == 333)

        let reopened = ResultsTableController(model: model, player: table.player)
        reopened.update()
        #expect(reopened.tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("title"))?.width == 333)
    }

    /// 50,000 tracks in 20,000 groups: matching, loading the outline and
    /// filtering should each take moments, not minutes.
    @Test func largeResultsStayQuick() async throws {
        let tracks = (0..<50_000).map { i in
            Fixtures.track(i, "Song \(i % 20_000)", "Artist \(i % 20_000 % 500)", size: Int64(i))
        }
        let model = ResultsModel(defaults: storage.defaults)
        let clock = ContinuousClock()
        let matching = try await clock.measure {
            model.load(tracks)
            try await waitForMatching(model)
        }
        #expect(model.groups.count == 20_000)

        let table = ResultsTableController(model: model, player: PlayerModel(defaults: storage.defaults))
        let loading = clock.measure { table.update() }
        #expect(table.tableView.numberOfRows == 70_000)

        let filtering = clock.measure { model.filter.text = "song 1999" }
        let reloading = clock.measure { table.update() }
        print("50k tracks: matching \(matching), loading \(loading), filtering \(filtering), reloading \(reloading)")
        #expect(loading < .seconds(3))
        #expect(filtering < .seconds(1))
    }
}

extension ResultsTableTests {
    @Test func filteringOutASelectedCopyDeselectsIt() async throws {
        let (model, table) = try await makeTable()
        table.tableView.selectRowIndexes([1, 5], byExtendingSelection: false)
        #expect(model.selection == [0, 3])
        model.filter.text = "cafe"
        table.update()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.selection == [3])
        #expect(table.selectedTrackIDs == [3])
    }
}

/// The ▶ column, space, and the player following the selection.
extension ResultsTableTests {
    func playCell(_ table: ResultsTableController, row: Int) -> PlayCellView? {
        let column = table.tableView.column(withIdentifier: ResultsTableController.playColumnID)
        return table.tableView.view(atColumn: column, row: row, makeIfNecessary: false) as? PlayCellView
    }

    @Test func aCopySelectedOnItsOwnGoesIntoThePlayer() async throws {
        let (_, table) = try await makeTable()
        table.tableView.selectRowIndexes([2], byExtendingSelection: false)
        #expect(table.player.track?.id == 1)
        table.tableView.selectRowIndexes([1, 5], byExtendingSelection: false)
        #expect(table.player.track?.id == 1, "Several selected copies leave the player alone")
        table.tableView.keyDown(with: keyEvent(downArrow, modifiers: .command, keyCode: 125))
        #expect(table.player.track?.id == 3)
        #expect(!table.player.isPlaying)
    }

    @Test func spacePlaysAndPauses() async throws {
        let (_, table) = try await makeTable(playable: true)
        let player = table.player
        table.tableView.keyDown(with: keyEvent(" "))
        #expect(player.track == nil, "Nothing selected, nothing to play")

        table.tableView.selectRowIndexes([1], byExtendingSelection: false)
        table.tableView.keyDown(with: keyEvent(" "))
        #expect(player.nowPlaying == NowPlaying(trackID: 0, isPlaying: true))
        table.tableView.keyDown(with: keyEvent(" "))
        #expect(player.nowPlaying == NowPlaying(trackID: 0, isPlaying: false))
    }

    @Test func thePlayButtonSelectsAndPlaysItsRow() async throws {
        let (model, table) = try await makeTable(playable: true)
        let window = realise(table)
        defer { window.close() }
        let tableView = table.tableView
        #expect(playCell(table, row: 5)?.symbolName == nil)

        // The pointer moves over the row.
        let middle = tableView.convert(NSPoint(x: tableView.rect(ofRow: 5).midX, y: tableView.rect(ofRow: 5).midY), to: nil)
        tableView.mouseMoved(with: mouseEvent(.mouseMoved, at: middle, in: window))
        #expect(tableView.hoveredRow == 5)
        let cell = try #require(playCell(table, row: 5))
        #expect(cell.symbolName == "play.fill")
        try #require(cell.subviews.compactMap { $0 as? NSButton }.first).performClick(nil)
        #expect(model.selection == [3])
        #expect(table.player.nowPlaying == NowPlaying(trackID: 3, isPlaying: true))

        table.update()
        #expect(cell.symbolName == "pause.fill", "Under the pointer, the playing copy offers to pause")
        tableView.mouseExited(with: mouseEvent(.mouseExited, at: .zero, in: window))
        #expect(tableView.hoveredRow == -1)
        #expect(playCell(table, row: 5)?.symbolName == "speaker.wave.2.fill")
        #expect(playCell(table, row: 6)?.symbolName == nil)
        table.player.pause()
        table.update()
        #expect(playCell(table, row: 5)?.symbolName == "speaker.fill")
    }

    @Test func whilePlayingTheSelectionTakesOver() async throws {
        let (_, table) = try await makeTable(playable: true)
        let player = table.player
        table.tableView.selectRowIndexes([1], byExtendingSelection: false)
        player.seek(to: 1)
        player.play()
        table.tableView.selectRowIndexes([2], byExtendingSelection: false)
        #expect(player.nowPlaying == NowPlaying(trackID: 1, isPlaying: true))
        #expect(player.position >= 1, "Another copy carries on from the same point")

        table.tableView.selectRowIndexes([5], byExtendingSelection: false)
        #expect(player.nowPlaying == NowPlaying(trackID: 3, isPlaying: true))
        #expect(player.position == 0, "Another track starts from the top")
        player.pause()
    }
}
