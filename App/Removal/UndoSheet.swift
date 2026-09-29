import SwiftUI

/// Puts back the last removal as it opens, shows the progress, then what
/// happened.
struct UndoSheet: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var report: RemovalModel.Report?

    var body: some View {
        let removal = library.removal
        Group {
            if let report {
                RemovalReportView(report: report) { dismiss() }
            } else if case .undoing(let done, let total) = removal.activity {
                RemovalProgressView(title: "Putting back \(done.formatted()) of \(RemovalModel.files(total))…", done: done, total: total)
            } else {
                RemovalProgressView(title: "Putting back files…", done: 0, total: 1)
            }
        }
        .padding(20)
        .frame(width: 480)
        .interactiveDismissDisabled(report == nil)
        .task {
            report = await removal.undoLast() ?? RemovalModel.Report(summary: "There's no removal to undo.", failures: [])
        }
    }
}
