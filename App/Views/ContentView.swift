import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        @Bindable var library = library
        NavigationSplitView {
            FolderList()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            detail
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        if library.isScanning {
                            Button("Stop", systemImage: "stop.fill") { library.cancelScan() }
                                .help("Stop scanning")
                        } else {
                            Button("Scan", systemImage: "arrow.clockwise") { library.scan() }
                                .disabled(!library.canScan)
                                .help("Scan the folders for music")
                        }
                    }
                }
        }
        // Here rather than on the sidebar, which may be collapsed.
        .fileImporter(isPresented: $library.isChoosingFolders, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { library.addFolders(urls) }
        }
    }

    @ViewBuilder private var detail: some View {
        switch library.state {
        case .idle:
            NoScanView()
        case .scanning(let progress):
            ScanProgressView(progress: progress) { library.cancelScan() }
        case .finished(let summary):
            ResultsView(summary: summary)
        case .failed(let message):
            ContentUnavailableView("Scan Failed", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }
}
