import SwiftUI

/// The Settings window.
struct SettingsView: View {
    @AppStorage(PlayerModel.samePositionKey) private var switchesAtSamePosition = true

    var body: some View {
        Form {
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
