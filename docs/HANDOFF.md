# Handoff

Read this, then `CLAUDE.md`, `docs/SPEC.md` and `docs/ROADMAP.md`. Phase 6
is on branch `claude/phase-6-player`, committed locally but not pushed
(2026-09-29). Phases 0–5 are on `main`.

## Where we are

- Phases 0–6 are done. The app builds in Xcode 27 (Swift 6.4) with no
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
- The player has only played generated, silent files, in the app tests. The
  snapshots show the player bar and ▶ column, but nobody has listened to real
  music with it, clicked the ▶ buttons or dragged along the waveform.
- Nothing has been built on Linux since TagLib was added.

## Do this first

1. Run the app on a real music folder. Listen to a group: select a copy,
   press space, then click the other copies while it plays. Check the switch
   is quick and keeps the position, that dragging along the waveform seeks,
   and that the ▶ button appears on the row under the pointer.
2. Then start phase 7 (removal and auto-select).

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
- `Selection/`: `KeeperSelector`, `RemovalPlanner`, `RemovalExecutor` (through
  `FileMover`) and `RemovalLog`.
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
- `Views/`: `ContentView` (split view, Scan button, folder picker),
  `FolderList` (add, remove, drop), `ScanViews` (before the first scan,
  progress, and the scan report) and `SettingsView` (the Settings window).
- `AppFolders`: `~/Library/Application Support/Deduplicator`, which the removal
  log will share, and `~/Library/Caches/Deduplicator/Waveforms`.

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

## Next: phase 7 (removal and auto-select)

See `docs/ROADMAP.md` and SPEC §6 and §8: a confirm sheet, then the Bin or a
mirrored move through `RemovalExecutor`, the JSON log, undo of the last
removal, and auto-select with editable rules and a preview. The planning and
keeper logic in `DedupCore/Selection` is done and tested. Removal settings can
join the player's in `SettingsView`. The player should let go of a copy that's
removed while it's in the player. Then phase 8 (tag copying).
