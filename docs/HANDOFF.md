# Handoff

Read this, then `CLAUDE.md`, `docs/SPEC.md` and `docs/ROADMAP.md`. Phase 7
is on branch `claude/phase-7-removal`, committed locally but not pushed
(2026-09-29). Phases 0–6 are on `main`.

## Where we are

- Phases 0–7 are done. The app builds in Xcode 27 (Swift 6.4) with no
  warnings, and every test passes: the package tests (`swift test` or
  `scripts/test.sh`) and the app tests in `AppTests/` (⌘U in Xcode).
- Phase 5 added the results screen: the banded table with group headers,
  collapsing, tick boxes, highlighted differences, any tag as a column, header
  sorting, a text and confidence filter, the `k`, `d` and ⌘↓ keys, and the
  match settings inspector.
- Phase 6 added the player under the table: play, pause, a waveform to seek
  with, A/B switching between copies at the same position, the ▶ column,
  space and double-click to play, and a Settings window with the one player
  setting.
- Phase 7 added removal and auto-select: a confirm sheet (Bin or a mirrored
  folder, with warnings), moving in the background with progress and Stop,
  the JSON log, undo of the last removal (also after a relaunch), and an
  auto-select sheet with editable keeper rules and a live preview. Removal
  settings joined the player's in the Settings window.
- The removal tests move real files, but within a temporary folder that also
  stands in for the Bin, so `trashItem` itself has only run in the phase 3
  unit tests' fake. Nobody has removed real music with the app, or clicked
  through the sheets.
- The player has only played generated, silent files, in the app tests.
- Nothing has been built on Linux since TagLib was added.

## Do this first

1. Run the app on a copy of some real music, not the only copy. Auto-select,
   then remove to the Bin and undo; remove to a folder and undo; and check
   the files, the results and `RemovalLog.json` each time. Also listen to a
   group, as phase 6 asked.
2. Then start phase 8 (copying tags to the keeper).

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
  plus a **waveform**. Selecting a copy on its own puts it in the player;
  while playing, the selection takes over playback.
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
- `Selection/`: `KeeperSelector` (rules, and `choices` for each group's keeper),
  `RemovalPlanner` (Bin or mirrored folder, and `moveIntoFolders` to refuse a
  folder that would put files back in a scanned one), `RemovalExecutor`
  (through `FileMover`, with progress and stopping) and `RemovalLog`.
- `Results/`: `TrackColumn` (each column's title, cell text and sort key),
  `GroupDifferences` (which copies differ), `ResultFilter`, `SearchIndex`,
  `GroupOrder` and `GroupArrangement`.
- `Waveform/`: `Waveform`, the peak and average level of each slice of a
  track, kept to 1/255 so it saves and loads exactly, and resampled to the
  width being drawn.

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
- `WaveformReader.read` (macOS only): decodes a file with `AVAudioFile` and
  measures 1,000 slices with vDSP. It stops as soon as its task is cancelled.
- `WaveformCache`: one small JSON file per audio file, named by a hash of the
  path, size and modification date, with those stored inside to check. About
  3 KB each. Nothing prunes it yet.

## App map (`App/`)

- `DeduplicatorApp`: one `Window` and Settings. File menu: Add Folder… (⌘O),
  Scan (⌘R), Stop Scan (⌘.), Remove Marked Files… (⌘⌫) and Undo Removal of
  N Files. Edit menu: Auto-Select Keepers… and Unmark All.
- `Library/LibraryModel` (`@MainActor`, `@Observable`): the folders (kept in
  `UserDefaults`), scan state and issues. It owns the `ResultsModel`,
  `PlayerModel` and `RemovalModel`, hands the results each scan's tracks, and
  says which commands are available (`canScan`, `canRemove`, …). Commands wait
  while a sheet is up, because a window shows one sheet at a time.
- `Results/ResultsModel`: runs `MatchEngine` off the main actor after a scan and
  after settings change (with a 300 ms pause, cancelling any older run), and
  holds the filter, order, columns, widths, marks, selection and keeper rules.
  Match settings, the column layout and the rules are saved in
  `UserDefaults`. `remove` takes removed copies out (groups left with one copy
  go) and `restore` puts undone ones back and matches again. `generation`
  counts scans, since track IDs belong to one scan.
- `Results/Table/`: `ResultsTableController` drives a flat `ResultsTableView`
  (an `NSTableView`): a full-width `GroupHeaderView` row per group, then a row
  per copy, painted by `BandRowView`. It rebuilds rows when the model's
  `revision` changes and only refreshes tick boxes when `marksRevision` does,
  and the ▶ cells (`PlayCellView`) when the player's `nowPlaying` does. It
  hands a copy selected on its own to the player. `ResultsTableView` tracks
  the row under the pointer, for the ▶ button. `ResultsTable` puts it in
  SwiftUI.
- `Results/ResultsView`: the table, the player bar, the toolbar (confidence,
  order, columns, settings), the search field, the status bar and the scan
  report popover. `Results/MatchSettingsView` is the inspector.
- `Player/PlayerModel` (`@MainActor`, `@Observable`, owned by `LibraryModel`):
  the copy in the player, `AVAudioPlayer` playback, the position (followed 20
  times a second while playing), and the waveform, drawn by a detached task
  that then draws the group's other copies into the cache. `select` is what
  the table calls; `play`, `pause`, `seek` and `unload` do the rest.
- `Player/PlayerBar` and `WaveformView`: the bar under the table. Only
  `PlayerTimeline` reads the position, so only it redraws while playing.
- `Removal/RemovalModel` (`@MainActor`, `@Observable`): plans with
  `RemovalPlanner`, moves with `RemovalExecutor` in a detached task, keeps the
  log, and undoes the last removal. It remembers each removal's tracks while
  their scan is loaded, so an undo can put them back in the results.
  `RemovalDestination` is the Bin-or-folder setting, kept in `UserDefaults`.
- `Removal/RemoveSheet`, `UndoSheet` and `AutoSelectSheet` (with
  `KeeperRulesEditor`): presented by `ContentView`, so menu commands work
  whatever the window shows. `RemovalViews` holds their shared parts.
- `Views/`: `ContentView` (split view, Scan button, folder picker, the
  sheets), `FolderList` (add, remove, drop), `ScanViews` (before the first
  scan, progress, and the scan report) and `SettingsView` (removal and player
  settings).
- `AppFolders`: `~/Library/Application Support/Deduplicator` (the scan cache
  and `RemovalLog.json`) and `~/Library/Caches/Deduplicator/Waveforms`.

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
- `AVAudioPlayer` opens a file in about 7 ms and seeks exactly, and rewinds to
  0 when it plays to the end. Stopping the old copy before starting the new
  one switches in 20–30 ms; pausing it instead took twice as long. `AVPlayer`
  would have meant waiting for each item to become ready before seeking.
- Overriding `scrollWheel` in the table would turn off responsive scrolling,
  so the ▶ hover follows scrolling through the clip view's bounds
  notifications instead.
- Hovering reads the real pointer, so it only counts in a visible window.
  Otherwise a test's off-screen window could pick up wherever the pointer is.
- If the chosen folder holds a scanned folder with the same name as its scan
  root, the mirrored destination is the file's own path, and the executor
  would rename the file in place. `RemovalPlanner.moveIntoFolders` catches
  that, along with folders inside a scanned folder.
- A SwiftUI `ForEach` over rule indices can read a removed row's binding once
  more, so the rules editor's bindings check the index.

## Next: phase 8 (copying tags to the keeper)

See `docs/ROADMAP.md` and SPEC §7: in a group, copy chosen tag values from any
copy to the keeper, and write them with `TagLibFile.write`, only to that file
and only after a confirmation showing the values before and after. There's no
free-form editor. Writing changes the file's size and date, so its scan-cache
and waveform entries miss next time, which is right; the results should take
the new values without a rescan. Then phase 9 (polish).
