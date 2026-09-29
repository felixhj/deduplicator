import AppKit
import DedupCore

/// Runs the results table: its rows, columns, sorting, collapsed groups,
/// marks and keyboard shortcuts, and which copy is in the player.
/// `ResultsTable` puts it into SwiftUI.
///
/// The table is flat: each group is a full-width header row followed by a row
/// per copy. Collapsing a group removes its copy rows. This is much faster
/// than an outline view, which takes over a second to expand 20,000 groups.
@MainActor
final class ResultsTableController: NSObject {
    let model: ResultsModel
    let player: PlayerModel
    let tableView = ResultsTableView()
    let scrollView = NSScrollView()

    private var items: [GroupItem] = []
    /// What each table row shows: a `GroupItem` header or a `CopyItem`.
    private var rows: [AnyObject] = []
    private var columnsByID: [String: TrackColumn] = [:]
    private var appliedRevision = -1
    private var appliedMarksRevision = -1
    private var appliedNowPlaying: NowPlaying?
    /// Groups the user collapsed, by `GroupItem.key`. Everything else is expanded.
    private var collapsedGroups: Set<Track.ID> = []
    /// True while the controller changes the table itself, so delegate
    /// callbacks don't feed those changes back into the model.
    private var isSyncing = false

    static let markColumnID = NSUserInterfaceItemIdentifier("mark")
    static let playColumnID = NSUserInterfaceItemIdentifier("play")
    /// The tick box and ▶ columns come first and stay there.
    static let fixedColumnCount = 2
    static let headerHeight: CGFloat = 26

    init(model: ResultsModel, player: PlayerModel) {
        self.model = model
        self.player = player
        super.init()
        configure()
    }

    // MARK: - Setup

    private func configure() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.style = .plain
        tableView.rowHeight = 20
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsTypeSelect = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.floatsGroupRows = true
        tableView.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        tableView.canSelectRow = { [weak self] row in self?.item(atRow: row) is CopyItem }
        tableView.hoverHandler = { [weak self] old, new in self?.hoverMoved(from: old, to: new) }
        tableView.target = self
        tableView.doubleAction = #selector(playClickedRow)
        tableView.menu = makeRowMenu()
        tableView.setAccessibilityLabel("Duplicate groups")

        // U+FE0E asks for the text triangle rather than the emoji.
        for (identifier, title, toolTip) in [(Self.markColumnID, "✓", "Marked for removal"), (Self.playColumnID, "\u{25B6}\u{FE0E}", "Play")] {
            let column = NSTableColumn(identifier: identifier)
            column.title = title
            column.headerToolTip = toolTip
            column.headerCell.alignment = .center
            column.width = 24
            column.minWidth = 24
            column.maxWidth = 24
            column.resizingMask = []
            tableView.addTableColumn(column)
        }

        let headerMenu = NSMenu()
        headerMenu.delegate = self
        tableView.headerView?.menu = headerMenu

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        // Scrolling moves rows under a pointer that stays still.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    // MARK: - Updates from the model

    func update() {
        syncColumns()
        syncSortIndicator()
        if model.revision != appliedRevision {
            appliedRevision = model.revision
            appliedMarksRevision = model.marksRevision
            reload()
        } else if model.marksRevision != appliedMarksRevision {
            appliedMarksRevision = model.marksRevision
            refreshMarks()
        }
        if player.nowPlaying != appliedNowPlaying {
            appliedNowPlaying = player.nowPlaying
            refreshPlayCells()
        }
    }

    private func reload() {
        let selected = selectedTrackIDs
        items = model.shownGroups.enumerated().map { index, group in
            let item = GroupItem(group: group, band: index % 2)
            item.copies = group.trackIDs.compactMap { id in
                model.tracks[id].map { CopyItem(track: $0, group: item) }
            }
            return item
        }
        rows = items.flatMap { item in [item] + (isExpanded(item) ? item.copies : []) }
        isSyncing = true
        defer { isSyncing = false }
        tableView.reloadData()
        let selectedRows = rows.indices.filter { selected.contains((rows[$0] as? CopyItem)?.track.id ?? -1) }
        tableView.selectRowIndexes(IndexSet(selectedRows), byExtendingSelection: false)
        // Copies the reload hid are no longer selected. SwiftUI is mid-update
        // here, so the model hears about it just afterwards.
        let stillSelected = selectedTrackIDs
        if stillSelected != model.selection {
            Task { @MainActor [weak self] in self?.model.selection = stillSelected }
        }
        tableView.updateHover()
    }

    func item(atRow row: Int) -> AnyObject? {
        rows.indices.contains(row) ? rows[row] : nil
    }

    func row(of item: AnyObject) -> Int? {
        rows.firstIndex { $0 === item }
    }

    /// Updates tick boxes and group warnings in the rows on screen. Rows made
    /// later read the marks as they're made.
    private func refreshMarks() {
        let markColumn = tableView.column(withIdentifier: Self.markColumnID)
        tableView.enumerateAvailableRowViews { rowView, row in
            switch item(atRow: row) {
            case let copy as CopyItem:
                (rowView.view(atColumn: markColumn) as? MarkCellView)?.isMarked = model.marked.contains(copy.track.id)
            case let group as GroupItem:
                (rowView.view(atColumn: 0) as? GroupHeaderView)?.everyCopyMarked = model.isEveryCopyMarked(in: group.group)
            default:
                break
            }
        }
    }

    /// Updates the ▶ column in the rows on screen.
    private func refreshPlayCells() {
        let playColumn = tableView.column(withIdentifier: Self.playColumnID)
        let nowPlaying = player.nowPlaying
        tableView.enumerateAvailableRowViews { rowView, row in
            guard let copy = item(atRow: row) as? CopyItem else { return }
            (rowView.view(atColumn: playColumn) as? PlayCellView)?
                .update(isCurrent: copy.track.id == nowPlaying.trackID, isPlaying: nowPlaying.isPlaying)
        }
    }

    /// Adds, removes and reorders table columns to match `model.columns`.
    private func syncColumns() {
        let wanted = model.columns
        columnsByID = Dictionary(uniqueKeysWithValues: wanted.map { ($0.id, $0) })
        isSyncing = true
        defer { isSyncing = false }
        for tableColumn in tableView.tableColumns
        where !Self.isFixed(tableColumn) && columnsByID[tableColumn.identifier.rawValue] == nil {
            tableView.removeTableColumn(tableColumn)
        }
        for (offset, column) in wanted.enumerated() {
            let identifier = NSUserInterfaceItemIdentifier(column.id)
            if tableView.column(withIdentifier: identifier) < 0 {
                tableView.addTableColumn(makeTableColumn(column))
            }
            let current = tableView.column(withIdentifier: identifier)
            if current != offset + Self.fixedColumnCount {
                tableView.moveColumn(current, toColumn: offset + Self.fixedColumnCount)
            }
        }
    }

    static func isFixed(_ tableColumn: NSTableColumn) -> Bool {
        tableColumn.identifier == markColumnID || tableColumn.identifier == playColumnID
    }

    private func makeTableColumn(_ column: TrackColumn) -> NSTableColumn {
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
        tableColumn.title = column.title
        tableColumn.headerToolTip = column.name
        tableColumn.headerCell.alignment = column.isNumeric ? .right : .left
        tableColumn.width = model.columnWidths[column.id].map { CGFloat($0) } ?? Self.defaultWidth(of: column)
        tableColumn.minWidth = 24
        tableColumn.maxWidth = 4000
        tableColumn.resizingMask = .userResizingMask
        tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.id, ascending: true)
        return tableColumn
    }

    static func defaultWidth(of column: TrackColumn) -> CGFloat {
        switch column {
        case .trackNumber, .discNumber: 34
        case .year, .channels: 46
        case .duration, .format, .bitDepth: 62
        case .bitrate, .sampleRate, .size: 76
        case .title, .fileName: 220
        case .artist, .album, .albumArtist, .comment: 160
        case .genre, .tag: 110
        case .modified: 130
        case .path: 380
        }
    }

    /// Shows the header sort arrow when groups are ordered by a column.
    private func syncSortIndicator() {
        var wanted: [NSSortDescriptor] = []
        if case .column(let column, let ascending) = model.order {
            wanted = [NSSortDescriptor(key: column.id, ascending: ascending)]
        }
        guard tableView.sortDescriptors != wanted else { return }
        isSyncing = true
        tableView.sortDescriptors = wanted
        isSyncing = false
    }

    // MARK: - Selection and marks

    var selectedTrackIDs: Set<Track.ID> {
        Set(tableView.selectedRowIndexes.compactMap { (item(atRow: $0) as? CopyItem)?.track.id })
    }

    private func markSelection(_ isMarked: Bool) {
        let ids = selectedTrackIDs
        guard !ids.isEmpty else { return }
        model.setMarked(ids, isMarked)
    }

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, let key = event.specialKey {
            switch key {
            case .downArrow: selectGroup(after: true); return true
            case .upArrow: selectGroup(after: false); return true
            default: return false
            }
        }
        guard modifiers.isEmpty else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case " ": togglePlayback(); return true
        case "d": markSelection(true); return true
        case "k": markSelection(false); return true
        default: return false
        }
    }

    /// Selects the first copy of the next or previous group, expanding it if needed.
    private func selectGroup(after forward: Bool) {
        guard !items.isEmpty else { return }
        let currentRow = forward ? tableView.selectedRowIndexes.last : tableView.selectedRowIndexes.first
        let current = currentRow.flatMap { (item(atRow: $0) as? CopyItem)?.group }
        let index = current.flatMap { group in items.firstIndex { $0 === group } }
        let target: Int
        switch (index, forward) {
        case (nil, _): target = forward ? 0 : items.count - 1
        case let (index?, true): target = min(index + 1, items.count - 1)
        case let (index?, false): target = max(index - 1, 0)
        }
        let group = items[target]
        setExpanded(group, true)
        guard let header = row(of: group), !group.copies.isEmpty else { return }
        tableView.selectRowIndexes([header + 1], byExtendingSelection: false)
        tableView.scrollRowToVisible(header)
        tableView.scrollRowToVisible(header + 1)
    }

    // MARK: - Playing

    /// A copy selected on its own goes into the player. Several selected
    /// copies don't, so selecting copies to mark them doesn't interrupt the
    /// one playing.
    private func followSelection() {
        let selected = tableView.selectedRowIndexes
        guard selected.count == 1, let copy = selected.first.flatMap(item(atRow:)) as? CopyItem else { return }
        player.select(copy.track, copies: copy.group.copies.map(\.track))
    }

    private func play(_ copy: CopyItem) {
        player.play(copy.track, copies: copy.group.copies.map(\.track))
    }

    /// Space plays or pauses. With nothing in the player, it plays the first selected copy.
    private func togglePlayback() {
        if player.track == nil, let copy = tableView.selectedRowIndexes.first.flatMap(item(atRow:)) as? CopyItem {
            play(copy)
        } else {
            player.togglePlayback()
        }
    }

    /// The ▶ button pauses or resumes the copy in the player, and selects and
    /// plays any other copy.
    private func playButtonClicked(_ id: Track.ID) {
        if player.track?.id == id { return player.togglePlayback() }
        guard let row = rows.firstIndex(where: { ($0 as? CopyItem)?.track.id == id }), let copy = rows[row] as? CopyItem else { return }
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        play(copy)
    }

    @objc private func playClickedRow() {
        guard let copy = item(atRow: tableView.clickedRow) as? CopyItem else { return }
        play(copy)
    }

    /// Shows the ▶ button on the row under the pointer only.
    private func hoverMoved(from old: Int, to new: Int) {
        let playColumn = tableView.column(withIdentifier: Self.playColumnID)
        for (row, isHovered) in [(old, false), (new, true)] where rows.indices.contains(row) {
            (tableView.view(atColumn: playColumn, row: row, makeIfNecessary: false) as? PlayCellView)?.isHovered = isHovered
        }
    }

    @objc private func scrolled() {
        tableView.updateHover()
    }

    // MARK: - Expanding and collapsing

    func isExpanded(_ group: GroupItem) -> Bool {
        !collapsedGroups.contains(group.key)
    }

    private func toggle(_ group: GroupItem, allGroups: Bool) {
        let expand = !isExpanded(group)
        if allGroups {
            if expand { collapsedGroups.removeAll() } else { collapsedGroups = Set(items.map(\.key)) }
            let selected = selectedTrackIDs
            rows = items.flatMap { item in [item] + (expand ? item.copies : []) }
            tableView.reloadData()
            let selectedRows = rows.indices.filter { selected.contains((rows[$0] as? CopyItem)?.track.id ?? -1) }
            tableView.selectRowIndexes(IndexSet(selectedRows), byExtendingSelection: false)
            tableView.updateHover()
        } else {
            setExpanded(group, expand)
        }
    }

    /// Shows or hides one group's copy rows.
    func setExpanded(_ group: GroupItem, _ expand: Bool) {
        guard isExpanded(group) != expand, let header = row(of: group) else { return }
        let copyRows = IndexSet(integersIn: (header + 1)..<(header + 1 + group.copies.count))
        if expand {
            collapsedGroups.remove(group.key)
            rows.insert(contentsOf: group.copies as [AnyObject], at: header + 1)
            tableView.insertRows(at: copyRows, withAnimation: [])
        } else {
            collapsedGroups.insert(group.key)
            rows.removeSubrange((header + 1)..<(header + 1 + group.copies.count))
            tableView.removeRows(at: copyRows, withAnimation: [])
        }
        (tableView.view(atColumn: 0, row: header, makeIfNecessary: false) as? GroupHeaderView)?.isExpanded = expand
        tableView.updateHover()
    }

    // MARK: - Menus

    private func makeRowMenu() -> NSMenu {
        let menu = NSMenu()
        let mark = NSMenuItem(title: "Mark for Removal", action: #selector(markSelected), keyEquivalent: "d")
        let keep = NSMenuItem(title: "Keep", action: #selector(keepSelected), keyEquivalent: "k")
        let copyTags = NSMenuItem(title: "Copy Tags from This Copy…", action: #selector(copyTagsFromSelected), keyEquivalent: "")
        let reveal = NSMenuItem(title: "Show in Finder", action: #selector(revealSelected), keyEquivalent: "")
        for item in [mark, keep] { item.keyEquivalentModifierMask = [] }
        for item in [mark, keep, copyTags, reveal] { item.target = self }
        menu.items = [mark, keep, .separator(), copyTags, reveal]
        return menu
    }

    @objc private func copyTagsFromSelected() {
        guard let id = selectedTrackIDs.first, selectedTrackIDs.count == 1 else { return }
        model.tagCopyRequest = TagCopyRequest(source: id)
    }

    @objc private func markSelected() { markSelection(true) }
    @objc private func keepSelected() { markSelection(false) }

    @objc private func revealSelected() {
        let urls = selectedTrackIDs.compactMap { model.tracks[$0]?.url }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc private func toggleColumn(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let column = TrackColumn(id: id) else { return }
        model.toggleColumn(column)
    }

    @objc private func restoreDefaultColumns() {
        model.restoreDefaultColumns()
    }

    private func columnMenuItem(_ column: TrackColumn) -> NSMenuItem {
        let item = NSMenuItem(title: column.name, action: #selector(toggleColumn(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = column.id
        item.state = model.columns.contains(column) ? .on : .off
        return item
    }
}

// MARK: - NSMenuDelegate, NSMenuItemValidation

extension ResultsTableController: NSMenuDelegate, NSMenuItemValidation {
    /// Builds the column menu, shown by right-clicking the header, each time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for column in TrackColumn.builtIn {
            menu.addItem(columnMenuItem(column))
        }
        menu.addItem(.separator())
        let tags = NSMenuItem(title: "Tags", action: nil, keyEquivalent: "")
        let tagMenu = NSMenu()
        if model.tagKeys.isEmpty {
            tagMenu.addItem(withTitle: "No Tags Found", action: nil, keyEquivalent: "")
        }
        for key in model.tagKeys {
            tagMenu.addItem(columnMenuItem(.tag(key)))
        }
        tags.submenu = tagMenu
        menu.addItem(tags)
        menu.addItem(.separator())
        let restore = NSMenuItem(title: "Restore Default Columns", action: #selector(restoreDefaultColumns), keyEquivalent: "")
        restore.target = self
        menu.addItem(restore)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(markSelected), #selector(keepSelected), #selector(revealSelected): !selectedTrackIDs.isEmpty
        case #selector(copyTagsFromSelected): selectedTrackIDs.count == 1
        default: true
        }
    }
}

// MARK: - NSTableViewDataSource

extension ResultsTableController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isSyncing, let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key, let column = TrackColumn(id: key)
        else { return }
        model.order = .column(column, ascending: descriptor.ascending)
    }
}

// MARK: - NSTableViewDelegate

extension ResultsTableController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        item(atRow: row) is GroupItem
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        item(atRow: row) is GroupItem ? Self.headerHeight : tableView.rowHeight
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        item(atRow: row) is CopyItem
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = tableView.makeView(withIdentifier: BandRowView.identifier, owner: self) as? BandRowView ?? {
            let view = BandRowView()
            view.identifier = BandRowView.identifier
            return view
        }()
        switch item(atRow: row) {
        case let group as GroupItem:
            rowView.isHeader = true
            rowView.band = group.band
        case let copy as CopyItem:
            rowView.isHeader = false
            rowView.band = copy.group.band
        default:
            break
        }
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch item(atRow: row) {
        case let group as GroupItem:
            let view = tableView.makeView(withIdentifier: GroupHeaderView.identifier, owner: self) as? GroupHeaderView ?? GroupHeaderView()
            view.configure(
                title: group.title,
                detail: group.detail,
                isExpanded: isExpanded(group),
                everyCopyMarked: model.isEveryCopyMarked(in: group.group)
            ) { [weak self] allGroups in
                self?.toggle(group, allGroups: allGroups)
            }
            return view
        case let copy as CopyItem:
            guard let identifier = tableColumn?.identifier else { return nil }
            if identifier == Self.markColumnID {
                let view = tableView.makeView(withIdentifier: MarkCellView.identifier, owner: self) as? MarkCellView ?? MarkCellView()
                view.configure(trackID: copy.track.id, isMarked: model.marked.contains(copy.track.id)) { [weak self] id in
                    self?.model.toggleMark(id)
                }
                return view
            }
            if identifier == Self.playColumnID {
                let view = tableView.makeView(withIdentifier: PlayCellView.identifier, owner: self) as? PlayCellView ?? PlayCellView()
                let id = copy.track.id
                view.configure(isCurrent: player.track?.id == id, isPlaying: player.isPlaying, isHovered: row == self.tableView.hoveredRow) { [weak self] in
                    self?.playButtonClicked(id)
                }
                return view
            }
            guard let column = columnsByID[identifier.rawValue] else { return nil }
            let view = tableView.makeView(withIdentifier: TextCellView.identifier, owner: self) as? TextCellView ?? TextCellView()
            view.configure(
                text: column.text(for: copy.track),
                isNumeric: column.isNumeric,
                differs: copy.group.differs(copy.track.id, in: column)
            )
            return view
        default:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, shouldReorderColumn columnIndex: Int, toColumn newColumnIndex: Int) -> Bool {
        columnIndex >= Self.fixedColumnCount && newColumnIndex >= Self.fixedColumnCount
    }

    func tableViewColumnDidMove(_ notification: Notification) {
        guard !isSyncing else { return }
        model.columns = tableView.tableColumns.compactMap { columnsByID[$0.identifier.rawValue] }
    }

    func tableViewColumnDidResize(_ notification: Notification) {
        guard !isSyncing, let tableColumn = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
              !Self.isFixed(tableColumn)
        else { return }
        model.columnWidths[tableColumn.identifier.rawValue] = Double(tableColumn.width)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncing else { return }
        model.selection = selectedTrackIDs
        followSelection()
    }
}
