# CLAUDE.md

Guidance for Claude Code (and humans) working in this repository.

## What this is

Deduplicator is a native macOS app that finds duplicate music files by comparing
**normalised tag values**, mainly title and artist, with constraints such as
decoded duration and track number. It shows grouped matches, lets the user
listen to and inspect every copy, then trashes the rejected files or moves them
to a folder.

**Picking up from an earlier session? Read `docs/HANDOFF.md` first.**

The source of truth for requirements is `docs/SPEC.md`. Build order is in
`docs/ROADMAP.md`. Update both when scope changes.

## Architecture

The code is split into three layers. Keep the boundaries strict.

1. **`DedupCore`** is pure Swift with no AppKit, SwiftUI or AVFoundation. It
   holds:
   - `Track`, a plain value type with the tags already read, the duration and
     file info
   - the normalisation pipeline (`NormalisationOptions` toggles applied by `Normaliser`)
   - similarity metrics (exact, token-based, Jaro-Winkler and Levenshtein
     ratios)
   - `MatchCriteria` and the grouping engine (blocking plus union-find)
   - auto-select ("keeper") rules, and the removal plan and executor
   - the results logic behind the table (`Results/`): column values, which
     cells differ within a group, filtering and ordering groups
   - `Waveform`: a track's peak and average level over time, for the player

   It must compile and pass its tests on Linux (`swift test`), so Claude can
   verify it in the cloud container, which has no Xcode.
2. **`DedupScanner`** turns folders into `Track`s. It finds audio files, reads
   tags and stream properties with TagLib, measures decoded duration with
   `AVAudioFile`, and keeps the scan cache. It also draws the player's
   waveforms (`WaveformReader`) and keeps them on disk (`WaveformCache`).
   TagLib is vendored as source in **`CTagLib`**, a C++ target with a small C
   interface, so Swift needs no C++ interop (see `Sources/CTagLib/README.md`).
   Both are package targets, so they build and test with `swift test` without
   Xcode. AVFoundation code sits behind `#if canImport(AVFoundation)`, so the
   rest should also build on Linux.
3. **`App/`** (the macOS app, built from `project.yml` with XcodeGen) holds the
   SwiftUI/AppKit UI and the player, and ties the other two together. It
   depends on the `DedupCore` and `DedupScanner` products. The results table is
   an `NSTableView` (see `App/Results/Table/`). The player (`App/Player/`)
   plays through `AVAudioPlayer`. `App/Removal/` runs removal, undo and
   auto-select; every file it moves goes through `RemovalExecutor`.
   `App/Tags/` copies tags between copies; every tag it writes goes through
   `TagLibFile.write`, and is logged. `App/AppIcon.icon` is the app icon, an
   Icon Composer file. `App/Updates/` asks GitHub for the latest release at
   launch. `AppTests/` holds tests hosted in the
   app, for the models, the table, the player, removal and tag copying. The
   player tests play silent files, and the removal and tag tests change real
   files within their own temporary folder, which also stands in for the Bin.

## Conventions

- Swift 6 with strict concurrency. Prefer value types and `Sendable`.
- Normalisation rules are **individually toggleable and unit-tested**. Every new
  rule needs test cases, including cases where it must *not* change the input.
- Duration always comes from the decoded audio, never from the TLEN or length
  tag.
- Targets macOS 15+, for personal use with no sandbox. Design for 50k+ tracks:
  never do O(n²) work without blocking, and keep heavy work off the main actor.
- Stripping and normalisation rules are **off by default**. Presets switch them
  on.
- Destructive file operations go through one service. Nothing is deleted
  permanently: files only go to the Bin or a user-chosen folder. Log every
  operation.
- UI copy uses British English ("Bin", "normalise").
- When a feature is added or changes, add what a person should check by hand
  to `docs/TESTING.md`.
- Keep functions small. Add comments only where the intent isn't obvious.

## Commands

```sh
swift build                 # build everything the host platform supports
scripts/test.sh             # run the package tests (wraps `swift test`, see below)
scripts/check-app.sh        # compile and link the app sources without Xcode
xcodegen && open Deduplicator.xcodeproj   # macOS app
xcodebuild -project Deduplicator.xcodeproj -scheme Deduplicator test   # every test (⌘U in Xcode)
scripts/build-release.sh    # universal release build, zipped in build/release/ for GitHub
```

To look at the results screen without clicking through the app, render it to
PNG files (light and dark mode) and open them:

```sh
TEST_RUNNER_SNAPSHOT_DIR=/tmp/shots xcodebuild -project Deduplicator.xcodeproj \
    -scheme Deduplicator test -only-testing:DeduplicatorTests/SnapshotTests
```

The capture can't draw SwiftUI's glass and material views, such as toolbar
buttons and the inspector's background, so those come out blank or garbled.
It also has no window background behind it, so anything see-through, such as
a `Divider`, comes out too light in dark mode.

## Environment notes for Claude

- Cloud sessions run on Linux with no Xcode. You can compile and test
  `DedupCore` there, if a Swift toolchain is installed. `CTagLib` and
  `DedupScanner` are meant to build there too (without AVFoundation, so no
  durations), but that hasn't been tried yet. Guard macOS-only code with
  `#if canImport(AppKit)` or `#if canImport(AVFoundation)`, or keep it in the
  app target, so `swift build` still works on Linux.
- Never claim UI or app code "works" without saying it was not compiled or run
  on macOS in the session.
- On a Mac with only the Command Line Tools (no Xcode), plain `swift test`
  fails with `no such module 'Testing'`: SwiftPM doesn't pass Swift Testing's
  framework path. `scripts/test.sh` adds the missing paths and otherwise runs
  plain `swift test`, so use it everywhere. Don't try to fix this in
  `Package.swift`: the generated test runner doesn't get the target's flags, so
  it builds but silently runs no tests.
- To run one Swift Testing test with `-only-testing`, include the parentheses:
  `DeduplicatorTests/ResultsTableTests/largeResultsStayQuick()`. Without them
  nothing runs, and the run still succeeds.
- Tests that make an `NSWindow` must set `isReleasedWhenClosed = false`, or
  closing it over-releases the window and crashes the test host later.
- Without Xcode there's no `xcodebuild`, so the app bundle can't be built.
  `scripts/check-app.sh` still compiles and links the app's Swift sources
  against the package as a bare executable. When that's the only check app code
  had, say so.
