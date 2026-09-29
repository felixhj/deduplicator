import AppKit

/// The results table. It hands key presses to its controller first, for the
/// k, d and ⌘↓ shortcuts.
final class ResultsTableView: NSTableView {
    /// Returns true when it handled the key.
    var keyHandler: ((NSEvent) -> Bool)?
    /// Whether a row can be selected, so a right-click only selects copies.
    var canSelectRow: ((Int) -> Bool)?

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
}
