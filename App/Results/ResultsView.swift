import DedupCore
import SwiftUI

/// Duplicate groups from the last scan, with the filter, order, columns and
/// match settings that shape them.
struct ResultsView: View {
    @Environment(LibraryModel.self) private var library
    let summary: ScanSummary
    @AppStorage("showsMatchSettings") private var showsSettings = true

    var body: some View {
        @Bindable var results = library.results
        VStack(spacing: 0) {
            ResultsTable(
                model: results,
                revision: results.revision,
                marksRevision: results.marksRevision,
                columns: results.columns,
                order: results.order
            )
            .overlay { EmptyResultsView(showsSettings: $showsSettings) }
            Divider()
            ResultsStatusBar(summary: summary)
        }
        .searchable(text: $results.filter.text, placement: .toolbar, prompt: "Filter")
        .toolbar {
            ToolbarItemGroup {
                ConfidenceMenu(minimum: $results.filter.minimumConfidence)
                OrderMenu(order: $results.order)
                ColumnsMenu(results: results)
                Toggle(isOn: $showsSettings) {
                    Label("Match Settings", systemImage: "slider.horizontal.3")
                }
                .help("Show or hide the match settings")
            }
        }
        .inspector(isPresented: $showsSettings) {
            MatchSettingsView(criteria: $results.criteria)
                .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
        }
    }
}

/// Shown over the table when there's nothing in it.
private struct EmptyResultsView: View {
    @Environment(LibraryModel.self) private var library
    @Binding var showsSettings: Bool

    var body: some View {
        let results = library.results
        if results.matchState == .finished, results.shownGroups.isEmpty {
            if results.groups.isEmpty {
                ContentUnavailableView {
                    Label("No Duplicates Found", systemImage: "checkmark.circle")
                } description: {
                    Text("Looser match settings may find more.")
                } actions: {
                    Button("Show Match Settings") { showsSettings = true }
                }
            } else {
                ContentUnavailableView("No Matching Groups", systemImage: "line.3.horizontal.decrease.circle", description: Text("No groups match the filter."))
            }
        }
    }
}

private struct ConfidenceMenu: View {
    @Binding var minimum: Double

    var body: some View {
        Menu {
            Picker("Minimum Confidence", selection: $minimum) {
                Text("Any Confidence").tag(0.0)
                ForEach([0.8, 0.9, 0.95, 1.0], id: \.self) { value in
                    Text(value == 1 ? "100% Only" : "\(Int(value * 100))% or More").tag(value)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Confidence", systemImage: "gauge.with.dots.needle.67percent")
        }
        .help("Only show groups matched with at least this confidence")
    }
}

private struct OrderMenu: View {
    @Binding var order: GroupOrder

    var body: some View {
        Menu {
            Picker("Order Groups By", selection: $order) {
                Text("Confidence").tag(GroupOrder.confidence)
                Text("Number of Copies").tag(GroupOrder.copies)
            }
            .pickerStyle(.inline)
            Text("Click a column heading to order by that column.")
        } label: {
            Label("Order", systemImage: "arrow.up.arrow.down")
        }
        .help("Choose how groups are ordered")
    }
}

private struct ColumnsMenu: View {
    let results: ResultsModel

    var body: some View {
        Menu {
            ForEach(TrackColumn.builtIn, id: \.id) { column in
                Toggle(column.name, isOn: binding(for: column))
            }
            Divider()
            Menu("Tags") {
                if results.tagKeys.isEmpty {
                    Text("No Tags Found")
                }
                ForEach(results.tagKeys, id: \.self) { key in
                    Toggle(key, isOn: binding(for: .tag(key)))
                }
            }
            Divider()
            Button("Restore Default Columns") { results.restoreDefaultColumns() }
        } label: {
            Label("Columns", systemImage: "tablecells")
        }
        .help("Choose the columns to show")
    }

    private func binding(for column: TrackColumn) -> Binding<Bool> {
        Binding(
            get: { results.columns.contains(column) },
            set: { _ in results.toggleColumn(column) }
        )
    }
}

/// Counts under the table, matching progress, and the scan report.
private struct ResultsStatusBar: View {
    @Environment(LibraryModel.self) private var library
    let summary: ScanSummary
    @State private var showsReport = false

    var body: some View {
        let results = library.results
        HStack(spacing: 12) {
            if case .matching(let progress) = results.matchState {
                ProgressView(value: progress)
                    .frame(width: 80)
                Text("Finding duplicates…")
            } else {
                Text(counts(results))
            }
            Spacer()
            if !results.marked.isEmpty {
                Text("\(results.marked.count.formatted()) marked for removal (\(TrackColumn.formatSize(results.markedSize)))")
            }
            Button("Scan Report") { showsReport = true }
                .buttonStyle(.link)
                .popover(isPresented: $showsReport) {
                    ScanSummaryView(summary: summary, issues: library.issues)
                        .frame(width: 380, height: 420)
                }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func counts(_ results: ResultsModel) -> String {
        let shown = results.shownGroups.count
        let total = results.groups.count
        let groups = shown == total
            ? plural(total, "duplicate group", "duplicate groups")
            : "\(shown.formatted()) of \(plural(total, "group", "groups"))"
        return "\(groups) · \(plural(results.shownCopyCount, "copy", "copies"))"
    }

    private func plural(_ count: Int, _ one: String, _ many: String) -> String {
        "\(count.formatted()) \(count == 1 ? one : many)"
    }
}
