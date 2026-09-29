# Handoff

Read this, then `CLAUDE.md`, `docs/SPEC.md` and `docs/ROADMAP.md`. Phase 4
is on branch `claude/phase-4-app-shell`, which was committed locally but not
pushed (2026-09-29).

## Where we are

- Phases 0–3 (the `DedupCore` engine) compile, and all their tests pass on
  macOS with Swift 6.3.3. They needed no code changes.
- Phase 4 is written:
  - `CTagLib` (TagLib 2.3.2, vendored, with a C interface) and `DedupScanner`
    (folder scanning, tag and duration reading, the scan cache) are package
    targets. Their tests pass on macOS, including end-to-end scans of real
    AAC, ALAC, FLAC, AIFF, WAV and MP3 files.
  - `project.yml` and a SwiftUI shell in `App/`: a folder list, Scan with
    progress and Stop, and a summary with any problems.
- The Mac used so far only has the Command Line Tools, so **the app hasn't been
  built in Xcode or run**. `scripts/check-app.sh` compiles and links its
  sources, and `xcodegen` generates a project that `plutil` accepts.
- Nothing has been built on Linux since TagLib was added.

## Do this first, on a Mac with Xcode

1. `scripts/test.sh`. All tests should pass.
2. `xcodegen && open Deduplicator.xcodeproj`, then build and run. Check:
   - Xcode resolves the Swift package, which sits in the project's own folder
     (`path: .`). XcodeGen always adds a local package twice: as a package
     reference and as a folder under "Packages". If Xcode objects, generate
     the project into a subfolder so it isn't next to `Package.swift`.
   - The C++ `CTagLib` target builds and links in Xcode.
   - Scanning a real music folder gives the right tags, formats and durations
     for a few files you know. A second scan should say most tracks came from
     the scan cache.
3. Then start phase 5.

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
- `LibraryModel` (`@MainActor`, `@Observable`): the folders (kept in
  `UserDefaults`), scan state, tracks and issues.
- `AppFolders`: `~/Library/Application Support/Deduplicator`, which the removal
  log will share.
- Views: `ContentView` (split view, toolbar, folder picker), `FolderList` (add,
  remove, drop) and `ScanStatusView` (progress, then a summary).

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

## Next: phase 5 (results UI)

See `docs/ROADMAP.md` and SPEC §4. After a scan, run `MatchEngine` off the main
actor with settings from a match settings panel. Then show the groups in one
flat banded table with collapsible groups, with columns for any key in
`Track.tags` and differing values highlighted. Try SwiftUI `Table` first, and
fall back to `NSTableView` if 50k rows are too slow.
