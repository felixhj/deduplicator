import DedupCore
import SwiftUI

/// Confirms removing the marked copies and where they go, shows the files
/// being moved, then any that couldn't be.
struct RemoveSheet: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage(RemovalDestination.key) private var destination: RemovalDestination = .bin
    @AppStorage(RemovalDestination.folderKey) private var folderPath = ""
    @State private var report: RemovalModel.Report?
    /// Removing every copy of a track needs saying yes to.
    @State private var removesEveryCopy = false

    var body: some View {
        let removal = library.removal
        Group {
            if let report {
                RemovalReportView(report: report) { dismiss() }
            } else if case .removing(let done, let total) = removal.activity {
                RemovalProgressView(title: "Moving \(done.formatted()) of \(RemovalModel.files(total))…", done: done, total: total, stop: removal.stop)
            } else {
                confirmation
            }
        }
        .padding(20)
        .frame(width: 560)
        .interactiveDismissDisabled(removal.isBusy)
    }

    private var confirmation: some View {
        let results = library.results
        let tracks = results.marked.compactMap { results.tracks[$0] }.sorted { $0.url.path() < $1.url.path() }
        let mode = destination.mode(folderPath: folderPath)
        let plan = mode.map { RemovalPlanner.plan(tracks, mode: $0) } ?? []
        let intoScanned = RemovalPlanner.moveIntoFolders(library.folders, in: plan)
        let everyCopy = results.groupsWithEveryCopyMarked
        let shown = Set(results.shownGroups.flatMap(\.trackIDs))
        let hidden = tracks.count { !shown.contains($0.id) }

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tracks.count == 1 ? "Remove 1 File?" : "Remove \(tracks.count.formatted()) Files?")
                    .font(.headline)
                Text("They take up \(TrackColumn.formatSize(tracks.reduce(0) { $0 + $1.fileSize })). Nothing is deleted, and you can undo the removal afterwards.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !everyCopy.isEmpty {
                EveryCopyCallout(names: everyCopy.compactMap { $0.trackIDs.first.flatMap { results.tracks[$0]?.displayName } }, isConfirmed: $removesEveryCopy)
            }
            if hidden > 0 {
                RemovalWarning(text: hidden == 1
                    ? "One of them is in a group the filter hides."
                    : "\(hidden.formatted()) of them are in groups the filter hides.")
            }

            VStack(alignment: .leading, spacing: 8) {
                Picker("Move them to:", selection: $destination) {
                    Text("The Bin").tag(RemovalDestination.bin)
                    Text("A folder").tag(RemovalDestination.folder)
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                if destination == .folder {
                    HStack {
                        Text(folderPath.isEmpty ? "No folder chosen" : folderPath)
                            .foregroundStyle(folderPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") {
                            if let path = RemovalFolderChooser.choose(startingAt: folderPath) { folderPath = path }
                        }
                    }
                    if let move = intoScanned {
                        RemovalWarning(text: "Choose a folder outside the folders you scan. \(move.source.lastPathComponent) would go to \(move.destination?.path(percentEncoded: false) ?? ""), where a scan would find it.")
                    } else if let first = plan.first?.destination {
                        Text("Each file keeps the folders it was in below its scanned folder. The first goes to \(first.path(percentEncoded: false)).")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            DisclosureGroup("Files") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(tracks) { track in
                            Text(track.url.path(percentEncoded: false))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .font(.callout)
                    .padding(8)
                }
                .frame(height: 140)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(destination == .bin ? "Move to Bin" : "Move to Folder") {
                    if let mode { start(mode) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tracks.isEmpty || mode == nil || intoScanned != nil || (!everyCopy.isEmpty && !removesEveryCopy))
            }
        }
    }

    private func start(_ mode: RemovalMode) {
        Task {
            guard let report = await library.removal.removeMarked(to: mode) else { return dismiss() }
            if report.isComplete {
                dismiss()
            } else {
                self.report = report
            }
        }
    }
}

/// Names the tracks that would have no copy left, and asks for a tick before
/// they can be removed.
struct EveryCopyCallout: View {
    let names: [String]
    @Binding var isConfirmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(names.count == 1 ? "No copy of 1 track will be left" : "No copy of \(names.count.formatted()) tracks will be left")
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Text("Every copy of \(Self.list(names)) is marked.")
                .fixedSize(horizontal: false, vertical: true)
            Toggle(names.count == 1 ? "Remove every copy of this track" : "Remove every copy of these tracks", isOn: $isConfirmed)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.5)))
    }

    /// "A", "A and B", "A, B and C", or "A, B, C and 4 more".
    static func list(_ names: [String]) -> String {
        let shown = names.prefix(3).map { "“\($0)”" }
        let rest = names.count - shown.count
        if rest > 0 { return shown.joined(separator: ", ") + " and \(rest.formatted()) more" }
        guard shown.count > 1 else { return shown.first ?? "" }
        return shown.dropLast().joined(separator: ", ") + " and " + shown.last!
    }
}
