import SwiftUI

/// Every keyboard shortcut, including the ones in the table that have no
/// menu item, because single keys there would stop the filter taking them.
struct ShortcutsView: View {
    private static let sections: [(title: String, shortcuts: [(keys: String, action: String)])] = [
        ("In the Table", [
            ("↑  ↓", "Move between copies"),
            ("⌘↓  ⌘↑", "Go to the next or previous group"),
            ("D", "Mark the selected copies for removal"),
            ("K", "Keep the selected copies"),
            ("Space", "Play or pause"),
            ("←  →", "Skip back or forward 10 seconds"),
            ("Double-click", "Play a copy"),
            ("⌥-click a group", "Collapse or expand every group"),
        ]),
        ("Everywhere", [
            ("⌘O", "Add a folder"),
            ("⌘R", "Scan"),
            ("⌘.", "Stop scanning"),
            ("⌘F", "Find, by filtering the groups"),
            ("⌘⌫", "Remove the marked files"),
            ("⌥⌘I", "Show or hide the match settings"),
            ("⌥⌘S", "Show or hide the folders"),
            ("⌘,", "Settings"),
        ]),
    ]

    var body: some View {
        Form {
            ForEach(Self.sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.shortcuts, id: \.keys) { shortcut in
                        LabeledContent(shortcut.action) {
                            Text(shortcut.keys)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
