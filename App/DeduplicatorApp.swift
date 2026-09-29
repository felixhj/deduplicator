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
            }
        }
    }
}
