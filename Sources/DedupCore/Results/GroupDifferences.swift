/// Finds the cells to highlight because a copy's value differs from the rest
/// of its group.
public enum GroupDifferences {
    /// The tracks whose value in `column` isn't the group's single most common
    /// value. When all copies agree, that's none of them. When no value is more
    /// common than the others, as with two copies that disagree, it's all of them.
    public static func tracks(differingIn column: TrackColumn, among tracks: [Track]) -> Set<Track.ID> {
        guard column.highlightsDifferences, tracks.count > 1 else { return [] }
        let values = tracks.map { column.text(for: $0) }
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        guard counts.count > 1 else { return [] }
        let top = counts.values.max()!
        let commonest = counts.filter { $0.value == top }
        let majority = commonest.count == 1 ? commonest.first!.key : nil
        return Set(zip(tracks, values).filter { $0.1 != majority }.map(\.0.id))
    }
}
