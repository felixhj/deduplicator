import SwiftUI

@main
struct DeduplicatorApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var library = LibraryModel()
    @State private var updates = UpdateChecker()
    @AppStorage("showsMatchSettings") private var showsMatchSettings = true
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Deduplicator", id: "main") {
            ContentView()
                .environment(library)
                .environment(updates)
                .frame(minWidth: 720, minHeight: 420)
                .onAppear { appDelegate.isChangingFiles = { [library] in library.isChangingFiles } }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Deduplicator") { Self.showAboutPanel() }
                Button("Check for Updates…") { Task { await updates.checkNow() } }
            }
            CommandGroup(after: .sidebar) {
                Button(showsMatchSettings ? "Hide Match Settings" : "Show Match Settings") { showsMatchSettings.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .help) {
                Button("Deduplicator Help") { openWindow(id: "help") }
                    .keyboardShortcut("?")
                Button("Keyboard Shortcuts") { openWindow(id: "shortcuts") }
            }
            CommandGroup(after: .newItem) {
                Button("Add Folder…") { library.isChoosingFolders = true }
                    .keyboardShortcut("o")
                Divider()
                Button("Scan") { library.scan() }
                    .keyboardShortcut("r")
                    .disabled(!library.canScan)
                Button("Stop Scan") { library.cancelScan() }
                    .keyboardShortcut(".")
                    .disabled(!library.isScanning)
                Divider()
                Button("Remove Marked Files…") { library.removal.isConfirmingRemoval = true }
                    .keyboardShortcut(.delete)
                    .disabled(!library.canRemove)
                Button(undoTitle) { library.removal.isUndoing = true }
                    .disabled(!library.canUndoRemoval)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find…") { library.results.filterFocusRequests += 1 }
                    .keyboardShortcut("f")
                    .disabled(!library.hasResults)
                Divider()
                Button("Auto-Select Keepers…") { library.results.isAutoSelecting = true }
                    .disabled(!library.canAutoSelect)
                Button("Unmark All") { library.results.unmarkAll() }
                    .disabled(library.results.marked.isEmpty || library.removal.isBusy)
                Divider()
                Button("Copy Tags…") {
                    if let id = library.results.selection.first { library.results.tagCopyRequest = TagCopyRequest(source: id) }
                }
                .disabled(!library.canCopyTags)
            }
        }

        Settings {
            SettingsView()
        }

        Window("Keyboard Shortcuts", id: "shortcuts") {
            ShortcutsView()
        }
        .windowResizability(.contentSize)

        Window("Deduplicator Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
    }

    /// The standard panel, crediting the libraries the app is built on.
    private static func showAboutPanel() {
        let credits = NSAttributedString(
            string: "Finds duplicate music by comparing tags.\n\nReads and writes tags with TagLib (LGPL 2.1 or MPL 1.1) and utfcpp (Boost Software License).",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    /// "Undo Removal of 12 Files", so it's clear what goes back, even after a relaunch.
    private var undoTitle: String {
        guard let count = library.removal.undoable?.records.count else { return "Undo Last Removal" }
        return count == 1 ? "Undo Removal of 1 File" : "Undo Removal of \(count.formatted()) Files"
    }
}
