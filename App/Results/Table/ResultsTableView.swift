import AppKit

/// The results table. It hands key presses to its controller first, for the
/// space, k, d and ⌘↓ shortcuts, and keeps track of the row under the pointer.
final class ResultsTableView: NSTableView {
    /// Returns true when it handled the key.
    var keyHandler: ((NSEvent) -> Bool)?
    /// Whether a row can be selected, so a right-click only selects copies.
    var canSelectRow: ((Int) -> Bool)?
    /// Called with the old and new rows when the pointer moves to another row.
    var hoverHandler: ((_ old: Int, _ new: Int) -> Void)?
    /// The row under the pointer, or -1.
    private(set) var hoveredRow = -1
    private var hoverArea: NSTrackingArea?

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }

    /// Right-clicking a row that isn't selected selects it first, so the
    /// context menu acts on the row under the pointer.
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, !selectedRowIndexes.contains(row), canSelectRow?(row) ?? true {
            selectRowIndexes([row], byExtendingSelection: false)
        }
        return super.menu(for: event)
    }

    // MARK: - Hovering

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if hoverArea == nil {
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
            addTrackingArea(area)
            hoverArea = area
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHover(at: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHoveredRow(-1)
    }

    /// Finds the row under the pointer again, for when rows move under a
    /// pointer that stays still, as when scrolling.
    func updateHover() {
        guard let window, window.isVisible else { return setHoveredRow(-1) }
        updateHover(at: window.mouseLocationOutsideOfEventStream)
    }

    private func updateHover(at locationInWindow: NSPoint) {
        let point = convert(locationInWindow, from: nil)
        setHoveredRow(visibleRect.contains(point) ? row(at: point) : -1)
    }

    private func setHoveredRow(_ row: Int) {
        guard row != hoveredRow else { return }
        let old = hoveredRow
        hoveredRow = row
        hoverHandler?(old, row)
    }
}
