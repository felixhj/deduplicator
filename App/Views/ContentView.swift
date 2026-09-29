import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        @Bindable var library = library
        NavigationSplitView {
            FolderList()
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            ScanStatusView()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        if library.isScanning {
                            Button("Stop", systemImage: "stop.fill") { library.cancelScan() }
                        } else {
                            Button("Scan", systemImage: "arrow.clockwise") { library.scan() }
                                .disabled(!library.canScan)
                        }
                    }
                }
        }
        // Here rather than on the sidebar, which may be collapsed.
        .fileImporter(isPresented: $library.isChoosingFolders, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { library.addFolders(urls) }
        }
    }
}
