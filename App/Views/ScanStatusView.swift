import DedupCore
import DedupScanner
import SwiftUI

/// Shows scan progress, then a summary of what was found. The results table
/// replaces the summary in phase 5.
struct ScanStatusView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        switch library.state {
        case .idle:
            ContentUnavailableView {
                Label("No Scan Yet", systemImage: "music.note.list")
            } description: {
                Text(library.folders.isEmpty ? "Add a folder of music to get started." : "Scan your folders to find duplicates.")
            } actions: {
                Button("Scan") { library.scan() }
                    .disabled(!library.canScan)
            }
        case .scanning(let progress):
            ScanProgressView(progress: progress) { library.cancelScan() }
        case .finished(let summary):
            ScanSummaryView(summary: summary, issues: library.issues)
        case .failed(let message):
            ContentUnavailableView("Scan Failed", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }
}

private struct ScanProgressView: View {
    let progress: ScanProgress
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            switch progress.phase {
            case .finding:
                ProgressView()
                Text("Finding music files… \(progress.found.formatted()) found")
            case .reading:
                ProgressView(value: progress.fractionCompleted)
                    .frame(maxWidth: 360)
                Text("Reading \(progress.completed.formatted()) of \(progress.found.formatted()) files")
            case .saving:
                ProgressView()
                Text("Saving the scan cache…")
            }
            Button("Stop", action: cancel)
        }
        .monospacedDigit()
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScanSummaryView: View {
    let summary: ScanSummary
    let issues: [ScanIssue]

    var body: some View {
        Form {
            Section("Last Scan") {
                LabeledContent("Tracks", value: summary.trackCount.formatted())
                LabeledContent("From the scan cache", value: summary.cachedCount.formatted())
                LabeledContent("Time", value: summary.elapsed.formatted(.units(allowed: [.minutes, .seconds], fractionalPart: .show(length: 1))))
            }
            Section("Formats") {
                ForEach(summary.formatCounts, id: \.format) { entry in
                    LabeledContent(entry.format.displayName, value: entry.count.formatted())
                }
            }
            if !issues.isEmpty {
                Section("Problems (\(issues.count.formatted()))") {
                    ForEach(issues, id: \.self) { issue in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.url.lastPathComponent)
                            Text(issue.message)
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                        .help(issue.url.path(percentEncoded: false))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
