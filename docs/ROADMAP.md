# Roadmap

Each phase ends with a commit and push. The Linux column shows what Claude can
compile and test in the cloud container. Everything else has to be built and
checked on a Mac.

| Phase | Deliverable | Verifiable on Linux? |
|-------|-------------|----------------------|
| 0 | Repo scaffolding, CLAUDE.md, spec, roadmap | ✅ done |
| 1 | `DedupCore` foundations: `Track` model, text folding, the full set of toggleable normalisation rules (brackets, mix-class awareness, feat./collab artist splitting, "The", track-number prefixes, punctuation/diacritics), with tests | ✅ `swift test` |
| 2 | `DedupCore` matching: similarity metrics (Jaro-Winkler, Levenshtein ratio, token-set ratio), per-field levels, duration/track#/album/format constraints, blocking, union-find with anchor check, confidence and reasons, presets, with tests and a 50k synthetic benchmark | ✅ |
| 3 | `DedupCore` selection: auto-select keeper rules and a removal plan (Bin or mirrored-folder destinations), with tests | ✅ |
| 4 | App shell: `project.yml` (XcodeGen), TagLib integration, concurrent folder scanner, decoded duration via AVFoundation, scan cache | ❌ Mac |
| 5 | Results UI: flat banded table, collapsible groups, dynamic tag columns, diff highlighting, match settings panel | ❌ Mac |
| 6 | Player: AVPlayer transport, A/B at the same position, waveform | ❌ Mac |
| 7 | Removal: confirm sheet, Bin or mirrored move, JSON log, undo | ❌ Mac (the plan logic is tested in phase 3) |
| 8 | Basic tag editing: copy tags to the keeper via TagLib | ❌ Mac |
| 9 | Polish: settings persistence, presets UI, keyboard shortcuts, app icon | ❌ Mac |

## Key technical choices

- **TagLib** (C++) is used through a small Objective-C++ or C bridge in the app
  target, vendored via SwiftPM. It reads every tag frame and handles FLAC,
  AIFF and WAV reliably.
- **Duration** comes from `AVAudioFile` (frame length ÷ sample rate). This is
  the decoded length, not the tag.
- **Blocking:** candidates are bucketed by the normalised artist (per primary
  artist token) and by the normalised title prefix. Only pairs within a bucket
  are compared.
- **Table:** try SwiftUI `Table` with `TableColumnCustomization` first. Fall
  back to an `NSTableView` wrapped in `NSViewRepresentable` if 50k rows with
  dynamic columns turns out to be too slow.
