import AppKit

/// Holds quitting back while files are being moved or written, since
/// stopping part-way could leave a removal unlogged or a file half-saved.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the app once its model exists.
    @MainActor var isChangingFiles: () -> Bool = { false }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard isChangingFiles() else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Files Are Being Changed"
        alert.informativeText = "Deduplicator is moving or writing files. Quit once it has finished, or stop the removal first."
        alert.runModal()
        return .terminateCancel
    }
}
