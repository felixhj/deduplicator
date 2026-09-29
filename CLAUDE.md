# CLAUDE.md

Guidance for Claude Code (and humans) working in this repository.

## What this is

Deduplicator is a native macOS app that finds duplicate music files by comparing
**normalised tag values**, mainly title and artist, with constraints such as
decoded duration and track number. It shows grouped matches, lets the user
listen to and inspect every copy, then trashes the rejected files or moves them
to a folder.

The source of truth for requirements is `docs/SPEC.md`. Build order is in
`docs/ROADMAP.md`. Update both when scope changes.

## Architecture

The code is split into two layers. Keep this boundary strict.

1. **`DedupCore`** is pure Swift with no AppKit, SwiftUI or AVFoundation. It
   holds:
   - `Track`, a plain value type with the tags already read, the duration and
     file info
   - the normalisation pipeline, made of small composable `NormalisationRule`s
   - similarity metrics (exact, token-based, Jaro-Winkler and Levenshtein
     ratios)
   - `MatchCriteria` and the grouping engine (blocking plus union-find)
   - auto-select ("keeper") rules

   It must compile and pass its tests on Linux (`swift test`), so Claude can
   verify it in the cloud container, which has no Xcode.
2. **`App/` (the macOS app, built from `project.yml` with XcodeGen)** holds the SwiftUI/AppKit UI, folder
   scanning, tag reading and writing (TagLib bridge), audio duration measurement, the player and file
   operations (trash or move). It depends on `DedupCore`.

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
- Keep functions small. Add comments only where the intent isn't obvious.

## Commands

```sh
swift build                 # build everything the host platform supports
swift test                  # run DedupCore tests (works on Linux and macOS)
xcodegen && open Deduplicator.xcodeproj   # macOS app
```

## Environment notes for Claude

- Cloud sessions run on Linux with no Xcode. You can only compile and test
  `DedupCore` there, and only if a Swift toolchain is installed. Guard
  macOS-only code with `#if canImport(AppKit)` or keep it in the app target, so
  `swift build` still works on Linux.
- Never claim UI or app code "works" without saying it was not compiled or run
  on macOS in the session.
