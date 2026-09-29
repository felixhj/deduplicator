# Roadmap

Each phase ends with a commit and push. The Linux column shows what Claude can
compile and test in the cloud container. Everything else has to be built and
checked on a Mac.

| Phase | Deliverable | Verifiable on Linux? |
|-------|-------------|----------------------|
| 0 | Repo scaffolding, CLAUDE.md, spec, roadmap | ✅ done |
| 1 | `DedupCore` foundations: `Track` model, text folding, the full set of toggleable normalisation rules (brackets, mix-class awareness, feat./collab artist splitting, "The", track-number prefixes, punctuation/diacritics), with tests | ✅ done, tests pass on macOS |
| 2 | `DedupCore` matching: similarity metrics (Jaro-Winkler, Levenshtein ratio, token-set ratio), per-field levels, duration/track#/album/format constraints, blocking, union-find with anchor check, confidence and reasons, presets, with tests and a 50k synthetic benchmark | ✅ done, tests pass on macOS |
| 3 | `DedupCore` selection: auto-select keeper rules and a removal plan (Bin or mirrored-folder destinations), with tests | ✅ done, tests pass on macOS |
| 4 | App shell: `project.yml` (XcodeGen), TagLib integration, concurrent folder scanner, decoded duration via AVFoundation, scan cache | ✅ scanner and TagLib tested on macOS. ⚠️ The app shell compiles and links (`scripts/check-app.sh`) but hasn't been built in Xcode or run |
| 5 | Results UI: flat banded table, collapsible groups, dynamic tag columns, diff highlighting, match settings panel | ❌ Mac |
| 6 | Player: AVPlayer transport, A/B at the same position, waveform | ❌ Mac |
| 7 | Removal: confirm sheet, Bin or mirrored move, JSON log, undo | ❌ Mac (the plan logic is tested in phase 3) |
| 8 | Basic tag editing: copy tags to the keeper via TagLib | ❌ Mac |
| 9 | Polish: settings persistence, presets UI, keyboard shortcuts, app icon | ❌ Mac |

## Key technical choices

- **TagLib** (C++, currently 2.3.2) is vendored as source in the `CTagLib`
  package target and used through a small C interface, so Swift needs no C++
  interop. It reads every tag and handles FLAC, AIFF and WAV reliably.
- **Scanning** lives in the `DedupScanner` package target rather than the app
  target, so it can be tested with `swift test` without Xcode.
- **Duration** comes from `AVAudioFile` (frame length ÷ sample rate). This is
  the decoded length, not the tag.
- **Blocking:** candidates are bucketed by the normalised artist (per primary
  artist token) and by the normalised title prefix. Only pairs within a bucket
  are compared.
- **Table:** try SwiftUI `Table` with `TableColumnCustomization` first. Fall
  back to an `NSTableView` wrapped in `NSViewRepresentable` if 50k rows with
  dynamic columns turns out to be too slow.
