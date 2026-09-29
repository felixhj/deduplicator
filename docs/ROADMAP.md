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
| 4 | App shell: `project.yml` (XcodeGen), TagLib integration, concurrent folder scanner, decoded duration via AVFoundation, scan cache | ✅ done, built and run in Xcode |
| 5 | Results UI: flat banded table, collapsible groups, dynamic tag columns, diff highlighting, match settings panel | ✅ done. The results logic is tested anywhere; the table and models by app tests in Xcode |
| 6 | Player: transport, A/B at the same position, waveform | ✅ done. The waveform logic is tested anywhere, the waveform reader with `swift test` on a Mac, the player and table by app tests in Xcode |
| 7 | Removal: confirm sheet, Bin or mirrored move, JSON log, undo; auto-select keepers with editable rules and a preview (SPEC §6) | ✅ done. The plan, keeper, executor and log logic is tested anywhere; removal, undo and auto-select by app tests in Xcode, with real files |
| 8 | Basic tag editing: copy tags to the keeper via TagLib | ✅ done. The comparison logic is tested anywhere, re-reading a file with `swift test` on a Mac, and writing real files by app tests in Xcode |
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
- **Table:** an `NSTableView` in `NSViewRepresentable`. SwiftUI `Table` can't
  draw full-width group header rows or colour rows by group. The table is flat
  (a header row per group, then its copies) and handles collapsing itself,
  because an `NSOutlineView` took over a second to expand 20,000 groups. With
  50,000 tracks, loading takes under 0.1 s and filtering about 0.1 s.
- **Playback** uses `AVAudioPlayer` rather than `AVPlayer`. It opens a local
  file synchronously in about 7 ms, so switching copies takes 20–30 ms and the
  position carries over exactly, with no waiting for a player item to become
  ready.
- **Waveforms** are decoded with `AVAudioFile` and measured slice by slice with
  vDSP. Five minutes of FLAC or AAC takes about 0.15 s, even in a debug build.
