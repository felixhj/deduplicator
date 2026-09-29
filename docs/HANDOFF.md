# Handoff

Read this, then `CLAUDE.md`, `docs/SPEC.md` and `docs/ROADMAP.md`. Phase 5
is on branch `claude/phase-5-results-ui`, committed locally but not pushed
(2026-09-29). Phases 0–4 are on `main`.

## Where we are

- Phases 0–5 are done. The app builds in Xcode 27 (Swift 6.4) with no
  warnings, launches, and every test passes: the package tests (`swift test`
  or `scripts/test.sh`) and the app tests in `AppTests/` (⌘U in Xcode).
- Phase 5 added the results screen: the banded table with group headers,
  collapsing, tick boxes, highlighted differences, any tag as a column, header
  sorting, a text and confidence filter, the `k`, `d` and ⌘↓ keys, and the
  match settings inspector.
- Nobody has scanned a real music library with the app yet. Scans of
  generated audio files work, in the package tests and in an app test.
- Nothing has been built on Linux since TagLib was added.

## Do this first

1. Run the app on a real music folder. Check that groups make sense, that
   columns can be added, moved and resized and are remembered, and that the
   match settings change the groups.
2. Then start phase 6 (the player).

## Decisions already made with the user (don't re-ask)

- macOS 15+, for personal use with no App Sandbox. XcodeGen `project.yml`.
  Swift 6 with strict concurrency.
- Formats: MP3, AAC/M4A, ALAC, FLAC, AIFF, WAV. Tags are read and written with
  **TagLib**. Duration comes from the **decoded audio** (`AVAudioFile` frames ÷
  sample rate), never a tag.
- Scale: **50k+ tracks**. Needs a scan cache, concurrent scanning, blocking,
  and a virtualised table.
- Only folders are sources: no Music.app, Swinsian or Rekordbox import.
- **Every stripping rule is off by default.** Presets turn them on.
- UI: **one flat banded table** (like Swinsian) with collapsible groups. Columns
  can be resized, reordered and hidden, **any tag** can be added as a column,
  and values that differ within a group are highlighted.
- Player: A/B playback that keeps the same position when switching copies,
  plus a **waveform**.
- v1 extras: **undo of the last removal plus a JSON log**, **auto-select
  keepers**, **waveform**, and **basic tag editing** (copy chosen tag values
  from one copy to the keeper, with before/after confirmation).
- Removal: to the Bin (`trashItem`) or **move to a folder with the structure
  mirrored** (`Dest/<RootName>/relative/path`). Nothing is ever deleted
  permanently.
- Deferred until after v1: audio fingerprinting, library imports, a full tag
  editor.
- British English in the UI ("Bin", "normalise").

## Engine map (`Sources/DedupCore`)

- `Model/Track.swift`: `Track` (id, url, scanRoot, the main tag fields, decoded
  `duration`, `AudioProperties`, file size and date, and `tags` holding every
  tag) and `AudioFormat`.
- `Normalisation/`: `TextFolding`, `Brackets`, `VersionClassifier`,
  `CreditParser`, `NormalisationOptions` (with presets) and `Normaliser`.
- `Matching/`: `Similarity`, `MatchCriteria` (with presets) and
  `MatchEngine.findDuplicates(in:progress:)`, which blocks, compares in
  parallel and groups with union-find plus an anchor check.
- `Selection/`: `KeeperSelector`, `RemovalPlanner`, `RemovalExecutor` (through
  `FileMover`) and `RemovalLog`.
- `Results/`: `TrackColumn` (each column's title, cell text and sort key),
  `GroupDifferences` (which copies differ), `ResultFilter`, `SearchIndex`,
  `GroupOrder` and `GroupArrangement`.

## Scanner map (`Sources/DedupScanner`, `Sources/CTagLib`)

- `CTagLib`: TagLib's sources, hand-written `config/` headers, and
  `CTagLib.h`/`CTagLib.cpp`. The C interface opens a file read-only or
  writable, and returns audio properties with the codec (telling AAC and ALAC
  apart in MP4 files) and TagLib's unified property map. It can also set a
  property and save. Its README explains how to update TagLib.
- `TagLibFile.read` and `.write`: the Swift side of that interface.
- `DecodedAudio.read` (macOS only): `AVAudioFile` length ÷ sample rate, and
  the codec Core Audio reports.
- `FolderEnumerator`: resolves each folder's real path, so a folder that's a
  symbolic link is followed and the same folder is never scanned twice. File
  URLs are rebuilt under the folder the user chose, so they always start with
  `scanRoot`.
- `TrackBuilder`: TagLib properties to `Track` fields ("3/12" → 3, the first
  four-digit run → year), with several values joined by "; ". The format
  comes from TagLib's codec, then Core Audio's, then the extension.
- `AudioFileReader`: TagLib plus decoded duration. A file that fails still
  becomes a track, with its problems listed.
- `ScanCache`: JSON keyed by path and checked against size and modification
  date. Bump `ScanCache.version` when readers start storing something new.
- `LibraryScanner.scan(_:progress:)`: loads the cache while finding files,
  reads cache misses in a bounded task group, and reports progress at most ten
  times a second. Cancelling keeps what was read. It drops cache entries for
  deleted files, and only saves the cache when something changed. Tracks are
  sorted by path, and each `id` is its index.
- On an Apple silicon Mac, with 20,000 small MP3s already in the disk cache,
  the first scan took 1.6 s and a rescan 0.4 s. The cache is about 0.9 KB per
  track.

## App map (`App/`)

- `DeduplicatorApp`: one `Window`, with Add Folder… (⌘O), Scan (⌘R) and Stop
  Scan (⌘.) commands.
- `Library/LibraryModel` (`@MainActor`, `@Observable`): the folders (kept in
  `UserDefaults`), scan state and issues. It owns the `ResultsModel` and hands
  it each scan's tracks.
- `Results/ResultsModel`: runs `MatchEngine` off the main actor after a scan and
  after settings change (with a 300 ms pause, cancelling any older run), and
  holds the filter, order, columns, widths, marks and selection. Match
  settings and the column layout are saved in `UserDefaults`.
- `Results/Table/`: `ResultsTableController` drives a flat `ResultsTableView`
  (an `NSTableView`): a full-width `GroupHeaderView` row per group, then a row
  per copy, painted by `BandRowView`. It rebuilds rows when the model's
  `revision` changes and only refreshes tick boxes when `marksRevision` does.
  `ResultsTable` puts it in SwiftUI.
- `Results/ResultsView`: the table, the toolbar (confidence, order, columns,
  settings), the search field, the status bar and the scan report popover.
  `Results/MatchSettingsView` is the inspector.
- `Views/`: `ContentView` (split view, Scan button, folder picker),
  `FolderList` (add, remove, drop) and `ScanViews` (before the first scan,
  progress, and the scan report).
- `AppFolders`: `~/Library/Application Support/Deduplicator`, which the removal
  log will share.

## Things learned the hard way

- Without Xcode, `swift test` can't find Swift Testing. Use `scripts/test.sh`.
- `FileManager`'s URL enumerator returns real paths (`/private/var/...` for
  `/var/...`), and returns nothing for a root that is a symbolic link.
  `standardizedFileURL` and `resolvingSymlinksInPath()` strip `/private`
  instead, so only `realpath` matches the enumerator.
- TagLib opens any `.mp3`, even one with no MPEG frames. The C interface
  reports no audio stream for it, so the extension decides the format.
- Core Audio's FLAC encoder writes 24-bit files from float samples. The test
  fixtures encode from 16-bit integers. There's no MP3 encoder, so MP3
  fixtures are hand-made silent frames.

- An `NSOutlineView` took over a second to expand 20,000 groups, so the
  results table is a flat `NSTableView` that adds and removes a group's rows
  itself.
- Accent-insensitive `range(of:)` on every keystroke took 0.5 s over 50,000
  tracks. `SearchIndex` folds each track's text once instead.
- Xcode 27's SwiftPM builds with Swift Build, whose output layout differs from
  the older native build system's. `scripts/check-app.sh` handles both.
- Tests that make an `NSWindow` must set `isReleasedWhenClosed = false`.

## Next: phase 6 (player)

See `docs/ROADMAP.md` and SPEC §5: play, pause and seek with `AVPlayer`, a
waveform generated in the background and cached, and switching between copies
in a group at the same position. Space plays or pauses in the table, and the
▶ column from SPEC §4 comes with it. `ResultsModel.selection` already follows
the table's selection. Then phase 7 (removal and auto-select).
