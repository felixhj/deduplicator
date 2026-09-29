import DedupCore
import SwiftUI

/// Copies chosen tag values from one copy of a track to another, usually the
/// one being kept: pick the copies and tags, review the values before and
/// after, then write.
struct CopyTagsSheet: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss

    private enum Step: Equatable {
        case choosing
        case reviewing
        case writing
        case finished(String)
    }

    @State private var copies: [Track] = []
    @State private var sourceID: Track.ID
    @State private var destinationID: Track.ID?
    @State private var rows: [TagComparison] = []
    /// Keys whose value is copied.
    @State private var chosen: Set<String> = []
    @State private var unreadable: String?
    @State private var step = Step.choosing

    init(request: TagCopyRequest) {
        _sourceID = State(initialValue: request.source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch step {
            case .choosing: choosing
            case .reviewing: reviewing
            case .writing: RemovalProgressView(title: "Writing tags…", done: 0, total: 1)
            case .finished(let message): RemovalReportView(report: .init(summary: message, failures: [])) { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 640)
        .interactiveDismissDisabled(step == .writing)
        .onAppear {
            copies = library.results.copies(inGroupOf: sourceID)
            destinationID = library.tagWriter.defaultDestination(from: sourceID, among: copies)
            compare()
        }
    }

    private var source: Track? { copies.first { $0.id == sourceID } }
    private var destination: Track? { copies.first { $0.id == destinationID } }
    private var changes: [String: [String]] { TagCopy.changes(copying: chosen, in: rows) }

    // MARK: - Choosing

    private var choosing: some View {
        let copyable = rows.filter(\.canCopy)
        return Group {
            VStack(alignment: .leading, spacing: 4) {
                Text("Copy Tags").font(.headline)
                Text("Copies the ticked values from one copy of this track to another, usually the one you're keeping. Only that file is changed.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("From:").gridColumnAlignment(.trailing)
                    Picker("From", selection: $sourceID) {
                        ForEach(copies) { Text($0.copySummary).tag($0.id) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("To:")
                    Picker("To", selection: $destinationID) {
                        ForEach(copies.filter { $0.id != sourceID }) { copy in
                            Text(library.results.marked.contains(copy.id) ? copy.copySummary : "\(copy.copySummary) (kept)")
                                .tag(Optional(copy.id))
                        }
                    }
                    .labelsHidden()
                }
            }
            .onChange(of: sourceID) {
                if destinationID == sourceID || destinationID == nil {
                    destinationID = library.tagWriter.defaultDestination(from: sourceID, among: copies)
                }
                compare()
            }
            .onChange(of: destinationID) { compare() }

            if let unreadable {
                RemovalWarning(text: unreadable)
            } else if copyable.isEmpty {
                Text("The copies' tags are already the same, so there's nothing to copy.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Table(copyable) {
                    TableColumn("Copy") { row in
                        Toggle("Copy \(TagCopy.name(of: row.key))", isOn: tick(row.key))
                            .labelsHidden()
                    }
                    .width(40)
                    TableColumn("Tag") { row in
                        Text(TagCopy.name(of: row.key)).help(row.key)
                    }
                    .width(min: 90, ideal: 120)
                    TableColumn("Now") { row in
                        TagValue(values: row.destination)
                    }
                    TableColumn("Becomes") { row in
                        TagValue(values: row.source)
                    }
                }
                .frame(height: 240)
                let same = rows.count - copyable.count
                if same > 0 {
                    Text(same == 1 ? "1 more tag is the same, or has no value to copy." : "\(same) more tags are the same, or have no value to copy.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(changes.count == 1 ? "Review 1 Change…" : "Review \(changes.count) Changes…") { step = .reviewing }
                    .keyboardShortcut(.defaultAction)
                    .disabled(changes.isEmpty)
            }
        }
    }

    private func tick(_ key: String) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(key) },
            set: { if $0 { chosen.insert(key) } else { chosen.remove(key) } }
        )
    }

    /// Reads both files again, and ticks the gaps the source can fill.
    private func compare() {
        guard let source, let destination else { return rows = [] }
        let writer = library.tagWriter
        guard let from = writer.tags(of: source), let to = writer.tags(of: destination) else {
            unreadable = "The tags of \(writer.tags(of: source) == nil ? source.url.lastPathComponent : destination.url.lastPathComponent) can't be read. The file may have moved since the scan."
            rows = []
            return
        }
        unreadable = nil
        rows = TagCopy.compare(source: from, destination: to)
        chosen = Set(rows.filter(\.fillsGap).map(\.key))
    }

    // MARK: - Reviewing

    private var reviewing: some View {
        let changes = changes
        let changed = rows.filter { changes[$0.key] != nil }
        return Group {
            if let destination {
                Text(changes.count == 1 ? "Write 1 Tag to “\(destination.url.lastPathComponent)”?" : "Write \(changes.count) Tags to “\(destination.url.lastPathComponent)”?")
                    .font(.headline)
                Text(destination.url.path(percentEncoded: false))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            ScrollView {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                    ForEach(changed) { row in
                        GridRow {
                            Text(TagCopy.name(of: row.key)).fontWeight(.medium)
                            TagValue(values: row.destination).foregroundStyle(.secondary)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            TagValue(values: row.source)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Back") { step = .choosing }
                    .keyboardShortcut(.cancelAction)
                Button("Write Tags") { write(changes) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func write(_ changes: [String: [String]]) {
        guard let source, let destination else { return }
        let before = Dictionary(uniqueKeysWithValues: rows.filter { changes[$0.key] != nil }.map { ($0.key, $0.destination) })
        step = .writing
        Task {
            do {
                let problem = try await library.tagWriter.write(changes, before: before, to: destination, from: source)
                let written = changes.count == 1 ? "Wrote 1 tag" : "Wrote \(changes.count) tags"
                step = .finished(["\(written) to “\(destination.url.lastPathComponent)”.", problem].compactMap { $0 }.joined(separator: " "))
            } catch {
                step = .finished("The tags couldn't be written to “\(destination.url.lastPathComponent)”. \(TagWriter.describe(error))")
            }
        }
    }
}

/// A tag's values, or a dash for none.
private struct TagValue: View {
    let values: [String]

    var body: some View {
        let text = values.filter { !$0.isEmpty }.joined(separator: "; ")
        Text(text.isEmpty ? "—" : text)
            .foregroundStyle(text.isEmpty ? .secondary : .primary)
            .lineLimit(2)
            .truncationMode(.tail)
            .help(text)
    }
}
