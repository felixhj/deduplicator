import DedupCore
import SwiftUI

/// Every setting that decides what counts as a duplicate. Changes apply as you make them.
struct MatchSettingsView: View {
    @Binding var criteria: MatchCriteria

    var body: some View {
        Form {
            Section {
                Picker("Preset", selection: presetBinding) {
                    ForEach(MatchPreset.allCases) { preset in
                        Text(preset.title).tag(Optional(preset))
                    }
                    if MatchPreset(matching: criteria) == nil {
                        Text("Custom").tag(MatchPreset?.none)
                    }
                }
            } footer: {
                Text(MatchPreset(matching: criteria)?.summary ?? "Your own settings.")
                    .foregroundStyle(.secondary)
            }

            Section("Title") {
                FieldRuleEditor(label: "Compare", rule: $criteria.title)
            }

            Section("Artist") {
                FieldRuleEditor(label: "Compare", rule: $criteria.artist)
                Toggle("Match when one credit includes the other", isOn: $criteria.artistSubsetMatches)
                    .help("“A” matches “A & B”.")
            }

            Section("Constraints") {
                Toggle("Compare durations", isOn: durationEnabled)
                if let tolerance = criteria.durationTolerance {
                    LabeledContent("Within ±\(Int(tolerance)) s") {
                        Slider(value: durationBinding(tolerance), in: 0...30, step: 1)
                    }
                }
                ComparisonPicker(label: "Track number", comparison: $criteria.trackNumber)
                ComparisonPicker(label: "Album", comparison: $criteria.album)
                ComparisonPicker(label: "Format", comparison: $criteria.format, differentTitle: "Only across formats")
            }

            Section("Also Compare") {
                ForEach(TagField.allCases, id: \.self) { field in
                    Picker(field.name, selection: extraLevel(field)) {
                        ForEach(MatchLevel.allCases, id: \.self) { level in
                            Text(level.name).tag(level)
                        }
                    }
                }
            }

            Section("Title Clean-up") {
                Picker("Version text", selection: $criteria.normalisation.versionStripping) {
                    Text("Keep").tag(VersionStripping.off)
                    Text("Strip neutral labels").tag(VersionStripping.neutralOnly)
                    Text("Strip all versions").tag(VersionStripping.allVersions)
                }
                .help("Neutral labels are things like “Original Mix”, “Radio Edit” and “Remastered”. Stripping all versions also merges remixes, dubs and live versions.")
                Toggle("Strip everything in brackets", isOn: $criteria.normalisation.stripAllBrackets)
                Toggle("Strip “feat.” credits", isOn: $criteria.normalisation.stripFeaturedFromTitle)
                Toggle("Strip leading track numbers", isOn: $criteria.normalisation.stripTrackNumberPrefix)
                Toggle("Take the artist out of “Artist - Title”", isOn: $criteria.normalisation.splitArtistFromTitle)
                Toggle("Use “Artist - Title” file names when tags are missing", isOn: $criteria.normalisation.filenameFallback)
            }

            Section("Artist Clean-up") {
                Toggle("Ignore featured artists", isOn: $criteria.normalisation.separateFeaturedArtists)
                Toggle("Treat “A & B” and “B & A” as the same", isOn: $criteria.normalisation.splitCollaborations)
                Toggle("Ignore a leading “The”", isOn: $criteria.normalisation.ignoreLeadingThe)
            }

            Section("Text") {
                Toggle("Ignore case", isOn: $criteria.normalisation.ignoreCase)
                Toggle("Ignore accents", isOn: $criteria.normalisation.foldDiacritics)
                Toggle("Treat all dashes and quotes alike", isOn: $criteria.normalisation.unifyPunctuation)
                Toggle("Ignore punctuation", isOn: $criteria.normalisation.ignorePunctuation)
                Toggle("Treat “&” as “and”", isOn: $criteria.normalisation.ampersandAsAnd)
                Toggle("Ignore spaces", isOn: $criteria.normalisation.ignoreSpaces)
            }

            Section("Grouping") {
                Toggle("Match when title and artist are swapped", isOn: $criteria.detectSwappedFields)
                Toggle("Every copy must match the group’s first copy", isOn: $criteria.requireAnchorMatch)
                    .help("Stops a chain of near matches from joining two quite different tracks.")
            }

            Section {
                Button("Restore Standard Settings") { criteria = .standard }
                    .disabled(criteria == .standard)
            }
        }
        .formStyle(.grouped)
    }

    private var presetBinding: Binding<MatchPreset?> {
        Binding(
            get: { MatchPreset(matching: criteria) },
            set: { preset in if let preset { criteria = preset.criteria } }
        )
    }

    private var durationEnabled: Binding<Bool> {
        Binding(
            get: { criteria.durationTolerance != nil },
            set: { criteria.durationTolerance = $0 ? MatchCriteria.standard.durationTolerance : nil }
        )
    }

    private func durationBinding(_ tolerance: Double) -> Binding<Double> {
        Binding(get: { tolerance }, set: { criteria.durationTolerance = $0 })
    }

    /// Extra fields are stored as a list; `.ignore` means the field isn't in it.
    private func extraLevel(_ field: TagField) -> Binding<MatchLevel> {
        Binding(
            get: { criteria.extraFields.first { $0.field == field }?.rule.level ?? .ignore },
            set: { level in
                criteria.extraFields.removeAll { $0.field == field }
                if level != .ignore {
                    criteria.extraFields.append(ExtraFieldRule(field, FieldRule(level)))
                    criteria.extraFields.sort { TagField.allCases.firstIndex(of: $0.field)! < TagField.allCases.firstIndex(of: $1.field)! }
                }
            }
        )
    }
}

/// A match level, and for Similar and Fuzzy, how close the text must be.
private struct FieldRuleEditor: View {
    let label: String
    @Binding var rule: FieldRule

    var body: some View {
        Picker(label, selection: level) {
            ForEach(MatchLevel.allCases, id: \.self) { level in
                Text(level.name).tag(level)
            }
        }
        .help(rule.level.explanation)
        if rule.level == .similar || rule.level == .fuzzy {
            LabeledContent("At least \(Int((rule.threshold * 100).rounded()))% alike") {
                Slider(value: $rule.threshold, in: 0.5...1, step: 0.01)
            }
        }
    }

    /// Changing the level resets the threshold to that level's default.
    private var level: Binding<MatchLevel> {
        Binding(get: { rule.level }, set: { rule = FieldRule($0) })
    }
}

private struct ComparisonPicker: View {
    let label: String
    @Binding var comparison: Comparison
    var differentTitle = "Must be different"

    var body: some View {
        Picker(label, selection: $comparison) {
            Text("Any").tag(Comparison.any)
            Text("Must be the same").tag(Comparison.same)
            Text(differentTitle).tag(Comparison.different)
        }
    }
}

/// The engine's built-in settings, offered as starting points.
enum MatchPreset: String, CaseIterable, Identifiable {
    case standard, djLibrary, loose

    var id: Self { self }

    init?(matching criteria: MatchCriteria) {
        guard let preset = Self.allCases.first(where: { $0.criteria == criteria }) else { return nil }
        self = preset
    }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .djLibrary: "DJ Library"
        case .loose: "Loose"
        }
    }

    var summary: String {
        switch self {
        case .standard: "Title and artist must be the same, ignoring case, with durations within 3 seconds."
        case .djLibrary: "Strips mix labels such as “Original Mix” and featured credits, but keeps remixes apart."
        case .loose: "Groups every version of a song, including remixes, and tolerates spelling differences."
        }
    }

    var criteria: MatchCriteria {
        switch self {
        case .standard: .standard
        case .djLibrary: .djLibrary
        case .loose: .loose
        }
    }
}

extension MatchLevel {
    var name: String {
        switch self {
        case .identical: "Identical"
        case .same: "Same"
        case .similar: "Similar"
        case .fuzzy: "Fuzzy"
        case .ignore: "Ignore"
        }
    }

    var explanation: String {
        switch self {
        case .identical: "The tags must be exactly the same."
        case .same: "The tags must be the same after clean-up."
        case .similar: "The tags may differ by a few letters, such as a typo."
        case .fuzzy: "The tags may differ more, including word order."
        case .ignore: "This field isn’t compared."
        }
    }
}

extension TagField {
    var name: String {
        switch self {
        case .album: "Album"
        case .albumArtist: "Album artist"
        case .year: "Year"
        case .genre: "Genre"
        case .comment: "Comment"
        }
    }
}
