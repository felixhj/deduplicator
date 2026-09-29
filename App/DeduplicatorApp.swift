import SwiftUI

@main
struct DeduplicatorApp: App {
    @State private var library = LibraryModel()

    var body: some Scene {
        Window("Deduplicator", id: "main") {
            ContentView()
                .environment(library)
                .frame(minWidth: 720, minHeight: 420)
        }
        .commands {
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
                Button("Auto-Select Keepers…") { library.results.isAutoSelecting = true }
                    .disabled(!library.canAutoSelect)
                Button("Unmark All") { library.results.unmarkAll() }
                    .disabled(library.results.marked.isEmpty || library.removal.isBusy)
            }
        }

        Settings {
            SettingsView()
        }
    }

    /// "Undo Removal of 12 Files", so it's clear what goes back, even after a relaunch.
    private var undoTitle: String {
        guard let count = library.removal.undoable?.records.count else { return "Undo Last Removal" }
        return count == 1 ? "Undo Removal of 1 File" : "Undo Removal of \(count.formatted()) Files"
    }
}
