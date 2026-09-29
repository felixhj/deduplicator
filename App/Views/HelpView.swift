import SwiftUI

/// A short guide to using the app, from the Help menu.
struct HelpView: View {
    private static let sections: [(title: String, points: [String])] = [
        ("Find duplicates", [
            "Add the folders that hold your music: the + button under the folder list, File > Add Folder… (⌘O), or drag folders in from the Finder.",
            "Click Scan (⌘R). The first scan reads every file; later scans only read files that have changed.",
            "Each duplicate group gets a header row, with the copies under it. The header says how sure the match is and why the copies matched.",
        ]),
        ("Decide what counts as a duplicate", [
            "The match settings, beside the table, decide what matches. Show or hide them with the slider button or ⌥⌘I.",
            "Start from a preset: Standard, DJ Library or Loose. Changes apply as you make them.",
            "Save settings you like as your own preset with the … button beside Preset.",
        ]),
        ("Compare the copies", [
            "Values that differ between the copies in a group are highlighted.",
            "Right-click a column heading to add columns, including any tag in your files. Drag headings to reorder columns, drag the dividers to resize them, and double-click a divider to fit a column to its contents.",
            "Click a heading to sort by it. Filter with the search field (⌘F), or by confidence.",
        ]),
        ("Listen", [
            "Select a copy and press Space to play it. Click another copy of the same track while it plays, and it carries on from the same point, so you can hear the difference.",
            "Click or drag along the waveform to move through the track, or press ← and → to skip 10 seconds.",
        ]),
        ("Choose what to keep", [
            "Tick the copies to remove, or select copies and press D to mark them or K to keep them.",
            "Auto-Select (the wand) keeps the best copy in each group by rules you choose, such as lossless first, then the highest bitrate, and marks the rest. It shows what it will do before it does it.",
            "To keep one copy but use another's tags, right-click the other copy and choose Copy Tags from This Copy….",
            "A group whose every copy is marked shows a warning, since removing it would leave none of that track.",
        ]),
        ("Remove", [
            "Remove (the bin button, or ⌘⌫) moves the marked files to the Bin, or to a folder of your choice with their folders mirrored inside it. Nothing is deleted.",
            "Changed your mind? Undo, in the status bar or the File menu, puts the files back where they were, even after quitting.",
        ]),
        ("More", [
            "Settings (⌘,) chooses where removed files go, how the player switches copies, and whether to check for updates.",
            "Help > Keyboard Shortcuts lists every shortcut.",
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Self.sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.headline)
                        ForEach(section.points, id: \.self) { point in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•").foregroundStyle(.secondary)
                                Text(point).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, height: 620)
    }
}
