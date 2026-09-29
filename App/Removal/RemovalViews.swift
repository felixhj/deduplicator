import AppKit
import DedupCore
import SwiftUI

/// A removal or undo under way.
struct RemovalProgressView: View {
    let title: String
    let done: Int
    let total: Int
    /// Shown as a Stop button, when the work can be stopped.
    var stop: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .monospacedDigit()
            ProgressView(value: Double(done), total: Double(max(total, 1)))
            if let stop {
                HStack {
                    Spacer()
                    Button("Stop", action: stop)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }
}

/// What a removal or undo did, and the files it couldn't move.
struct RemovalReportView: View {
    let report: RemovalModel.Report
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report.summary)
                .fixedSize(horizontal: false, vertical: true)
            if !report.failures.isEmpty {
                FailureList(failures: report.failures)
            }
            HStack {
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct FailureList: View {
    let failures: [RemovalFailure]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(failures, id: \.self) { failure in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failure.source.lastPathComponent)
                            .fontWeight(.medium)
                        Text(failure.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(failure.source.path(percentEncoded: false))
                }
            }
            .padding(10)
        }
        .frame(maxHeight: 220)
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

/// A caution in a sheet.
struct RemovalWarning: View {
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

/// Asks for the folder removed files go to. The panel can make a new folder.
@MainActor
enum RemovalFolderChooser {
    /// The chosen folder's path, without a trailing slash.
    static func choose(startingAt path: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder removed files are moved to."
        if !path.isEmpty {
            panel.directoryURL = URL(filePath: path, directoryHint: .isDirectory)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let chosen = url.standardizedFileURL.path(percentEncoded: false)
        return chosen.count > 1 && chosen.hasSuffix("/") ? String(chosen.dropLast()) : chosen
    }
}
