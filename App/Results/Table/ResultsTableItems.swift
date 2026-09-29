import DedupCore

/// A duplicate group, shown as a header row. The table controller finds rows
/// by object identity, so groups and copies are classes.
final class GroupItem {
    let group: DuplicateGroup
    /// Groups alternate between two background colours.
    let band: Int
    var copies: [CopyItem] = []
    /// Tracks to highlight, by column ID, worked out when a column is first shown.
    private var differences: [String: Set<Track.ID>] = [:]

    init(group: DuplicateGroup, band: Int) {
        self.group = group
        self.band = band
    }

    /// Identifies the group across reorderings, to remember which groups are collapsed.
    var key: Track.ID { group.trackIDs.min() ?? -1 }

    func differs(_ trackID: Track.ID, in column: TrackColumn) -> Bool {
        if differences[column.id] == nil {
            differences[column.id] = GroupDifferences.tracks(differingIn: column, among: copies.map(\.track))
        }
        return differences[column.id]!.contains(trackID)
    }

    /// "Energy 52 – Café Del Mar", from the first copy.
    var title: String {
        copies.first?.track.displayName ?? ""
    }

    /// "3 copies · 97% · Same title · Same artist".
    var detail: String {
        let count = copies.count
        let confidence = "\(Int((group.confidence * 100).rounded()))%"
        return (["\(count) \(count == 1 ? "copy" : "copies")", confidence] + group.reasons.map(\.description))
            .joined(separator: " · ")
    }
}

/// One copy of a track, shown as a row under its group's header.
final class CopyItem {
    let track: Track
    unowned let group: GroupItem

    init(track: Track, group: GroupItem) {
        self.track = track
        self.group = group
    }
}

extension Track {
    /// "Energy 52 – Café Del Mar", or whichever of the two it has, or else the file name.
    var displayName: String {
        switch (artist.isEmpty, title.isEmpty) {
        case (false, false): "\(artist) – \(title)"
        case (true, false): title
        case (false, true): artist
        case (true, true): url.lastPathComponent
        }
    }
}
