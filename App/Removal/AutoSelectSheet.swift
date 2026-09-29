import DedupCore
import SwiftUI

/// Edits the rules that choose the copy to keep, previews what they'd mark
/// in the groups shown, and marks it.
struct AutoSelectSheet: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var results = library.results
        let choices = results.keeperChoices()
        let marks = choices.reduce(0) { $0 + $1.others.count }
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-Select Keepers")
                    .font(.headline)
                Text("Keeps the best copy in each group and marks the others for removal. The rules are tried in order, and the first that tells two copies apart decides.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            KeeperRulesEditor(rules: $results.keeperRules)
            Divider()
            KeeperPreview(choices: choices, results: results)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(marks == 1 ? "Mark 1 Copy" : "Mark \(marks.formatted()) Copies") {
                    results.apply(choices)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(choices.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620, height: 660)
    }
}

/// The keeper rules, in order. Rows can be dragged to reorder them.
struct KeeperRulesEditor: View {
    @Binding var rules: [KeeperRule]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List {
                ForEach(rules.indices, id: \.self) { index in
                    KeeperRuleRow(number: index + 1, rule: binding(at: index)) {
                        rules.remove(at: index)
                    }
                }
                .onMove { rules.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 190)
            .overlay {
                if rules.isEmpty {
                    Text("With no rules, the first copy in each group is kept.")
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Menu("Add Rule") {
                    ForEach(KeeperRule.plainRules, id: \.self) { rule in
                        Button(rule.description) { rules.append(rule) }
                            .disabled(rules.contains(rule))
                    }
                    Divider()
                    Button("Path Contains…") { rules.append(.pathContains("")) }
                    Button("Path Doesn't Contain…") { rules.append(.pathDoesNotContain("")) }
                    Button("Prefer a Format…") { rules.append(.preferFormat(.flac)) }
                }
                .fixedSize()
                Spacer()
                Button("Restore Default Rules") { rules = KeeperSelector.defaultRules }
                    .disabled(rules == KeeperSelector.defaultRules)
            }
        }
    }

    /// Checks the index, because SwiftUI can read a row's binding once more
    /// after the row is removed.
    private func binding(at index: Int) -> Binding<KeeperRule> {
        Binding(
            get: { rules.indices.contains(index) ? rules[index] : .preferLossless },
            set: { if rules.indices.contains(index) { rules[index] = $0 } }
        )
    }
}

private struct KeeperRuleRow: View {
    let number: Int
    @Binding var rule: KeeperRule
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(number).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            switch rule {
            case .pathContains(let text):
                Text("Path contains")
                TextField("Text", text: Binding(get: { text }, set: { rule = .pathContains($0) }), prompt: Text("Library"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            case .pathDoesNotContain(let text):
                Text("Path doesn't contain")
                TextField("Text", text: Binding(get: { text }, set: { rule = .pathDoesNotContain($0) }), prompt: Text("Downloads"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            case .preferFormat(let format):
                Picker("Prefer", selection: Binding(get: { format }, set: { rule = .preferFormat($0) })) {
                    ForEach(AudioFormat.allCases.filter { $0 != .unknown }, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .fixedSize()
            default:
                Text(rule.description)
            }
            Spacer()
            Button("Remove Rule", systemImage: "minus.circle", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Remove this rule")
        }
    }
}

/// What auto-select would do: how much it marks, then each group's keeper
/// and the copies it marks.
private struct KeeperPreview: View {
    let choices: [KeeperChoice]
    let results: ResultsModel

    var body: some View {
        let marked = choices.flatMap(\.others)
        let size = marked.reduce(Int64(0)) { $0 + (results.tracks[$1]?.fileSize ?? 0) }
        let copies = marked.count == 1 ? "1 copy" : "\(marked.count.formatted()) copies"
        let groups = choices.count == 1 ? "1 group" : "\(choices.count.formatted()) groups"
        let hidden = results.shownGroups.count < results.groups.count ? " Groups the filter hides are left alone." : ""
        VStack(alignment: .leading, spacing: 8) {
            Text("Marks \(copies) in \(groups), taking up \(TrackColumn.formatSize(size)), and replaces any marks in those groups.\(hidden)")
                .fixedSize(horizontal: false, vertical: true)
            List(choices, id: \.groupID) { choice in
                KeeperChoiceRow(choice: choice, tracks: results.tracks)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
        }
    }
}

private struct KeeperChoiceRow: View {
    let choice: KeeperChoice
    let tracks: [Track.ID: Track]

    var body: some View {
        if let keeper = tracks[choice.keeper] {
            VStack(alignment: .leading, spacing: 2) {
                Text(keeper.displayName)
                    .fontWeight(.medium)
                Text("Keeps \(keeper.copySummary)")
                Text("Marks \(choice.others.compactMap { tracks[$0]?.copySummary }.joined(separator: "; "))")
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.vertical, 2)
        }
    }
}
