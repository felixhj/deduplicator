import SwiftUI

/// The Settings window.
struct SettingsView: View {
    @AppStorage(PlayerModel.samePositionKey) private var switchesAtSamePosition = true
    @AppStorage(RemovalDestination.key) private var destination: RemovalDestination = .bin
    @AppStorage(RemovalDestination.folderKey) private var folderPath = ""
    @AppStorage(UpdateChecker.checksAtLaunchKey) private var checksForUpdates = true

    var body: some View {
        Form {
            Section {
                Picker("Removed files go to", selection: $destination) {
                    Text("The Bin").tag(RemovalDestination.bin)
                    Text("A folder").tag(RemovalDestination.folder)
                }
                .pickerStyle(.radioGroup)
                if destination == .folder {
                    LabeledContent("Folder") {
                        HStack {
                            Text(folderPath.isEmpty ? "None chosen" : folderPath)
                                .foregroundStyle(folderPath.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Choose…") {
                                if let path = RemovalFolderChooser.choose(startingAt: folderPath) { folderPath = path }
                            }
                        }
                    }
                }
            } header: {
                Text("Removal")
            } footer: {
                Text("Nothing is ever deleted. In a folder, each file keeps the folders it was in below its scanned folder. Every removal can be undone from the File menu.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Check for a new version when Deduplicator opens", isOn: $checksForUpdates)
            } header: {
                Text("Updates")
            } footer: {
                Text("Asks GitHub for the latest release. Nothing about you or your music is sent.")
                    .foregroundStyle(.secondary)
            }

            Section("Player") {
                Toggle(isOn: $switchesAtSamePosition) {
                    Text("Switch copies at the same position")
                    Text("While a copy plays, selecting another copy of the same track carries on from the same point, so you can compare them.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
