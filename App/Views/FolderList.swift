import SwiftUI

/// The folders to scan. Folders can be added with the + button, the Add
/// Folder command (the picker is in `ContentView`) or by dropping them on the list.
struct FolderList: View {
    @Environment(LibraryModel.self) private var library
    @State private var selection: Set<URL> = []

    var body: some View {
        List(selection: $selection) {
            Section("Folders") {
                ForEach(library.folders, id: \.self) { folder in
                    Label(folder.lastPathComponent, systemImage: "folder")
                        .help(folder.path(percentEncoded: false))
                }
            }
        }
        .overlay {
            if library.folders.isEmpty {
                ContentUnavailableView("No Folders", systemImage: "folder.badge.plus", description: Text("Add the folders that hold your music."))
            }
        }
        .onDeleteCommand { removeSelection() }
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            library.addFolders(folders)
            return !folders.isEmpty
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 0) {
                Button("Add Folder", systemImage: "plus") { library.isChoosingFolders = true }
                Button("Remove Folder", systemImage: "minus") { removeSelection() }
                    .disabled(selection.isEmpty || library.isScanning)
                Spacer()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    private func removeSelection() {
        guard !library.isScanning else { return }
        library.removeFolders(selection)
        selection = []
    }
}
