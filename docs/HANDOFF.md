# Handoff: cloud session → local Claude (VS Code)

Read this, then `CLAUDE.md`, `docs/SPEC.md` and `docs/ROADMAP.md`. Branch:
`claude/dazzling-dirac-3458nk`. It hasn't been merged to `main`, and there's no PR.

## Where we are

- Phases 0–3 (scaffolding plus the whole `DedupCore` engine) are written and
  pushed, but have **never been compiled or run**. The cloud container couldn't
  install Swift because `download.swift.org` was blocked. Expect some compile
  errors or test failures.
- Phases 4–9 (the Mac app) haven't been started. There's no `project.yml` or
  `App/` yet.

## Do this first

1. `swift build && swift test` in the repo root. Fix every compile error and
   failing test before touching the app. When a test fails, decide whether the
   code or the expectation is wrong. The expectations were reasoned out by hand,
   never run.
2. Then start phase 4.

## Decisions already made with the user (don't re-ask)

- macOS 15+, for personal use with no App Sandbox. XcodeGen `project.yml`.
  Swift 6 with strict concurrency.
- Formats: MP3, AAC/M4A, ALAC, FLAC, AIFF, WAV. Tags are read and written with
  **TagLib** (a C++ bridge in the app target). Duration comes from the
  **decoded audio** (`AVAudioFile` frames ÷ sample rate), never a tag.
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

- `Model/Track.swift` has `Track` (id: Int, url, scanRoot, title, artist,
  album, albumArtist, track/disc/year, comment, genre, decoded `duration`,
  `AudioProperties`, fileSize, modified, and `tags: [String: String]` holding
  every tag), `AudioFormat` (with `isLossless`, `supportedExtensions`).
- `Normalisation/`:
  - `TextFolding`: whitespace, dashes and quotes, diacritics (plus a manual map
    for ß, ø, æ and similar), `&`→and, punctuation, leading "The", splitting on
    a spaced dash.
  - `Brackets`: top-level `()[]{}` segments.
  - `VersionClassifier`: `.neutral` (Original Mix, Radio Edit, 2011 Remaster),
    `.distinct` (Remix, Dub, VIP, Live, Club Mix, "X Edit"), or `.notAVersion`
    (Part 2).
  - `CreditParser`: `splitFeatured`, `splitCollaborators`,
    `removingTrackNumberPrefix`.
  - `NormalisationOptions`: every toggle, plus `VersionStripping` (`off`,
    `neutralOnly`, `allVersions`). Presets are `.minimal` (the default),
    `.tidy`, `.djLibrary` and `.aggressive`.
  - `Normaliser`: produces `NormalisedTags` (title, sorted primary artists,
    featured artists, `removedFromTitle`).
- `Matching/`:
  - `Similarity`: Levenshtein ratio (used for Similar), and max of Jaro-Winkler
    and token-sort (used for Fuzzy).
  - `MatchCriteria`: a `FieldRule` (`MatchLevel` identical/same/similar/fuzzy/
    ignore, plus a threshold) for title and artist, `artistSubsetMatches`,
    `extraFields`, `durationTolerance` (default 3 s; nil means off; unknown
    durations pass), `Comparison` (any/same/different) for track number, album
    and format, `detectSwappedFields`, `requireAnchorMatch`. Presets are
    `.standard`, `.djLibrary` and `.loose`.
  - `MatchEngine.findDuplicates(in:progress:) async throws`:
    1. prepare
    2. block: on an exact title or artist key when possible, otherwise on
       tokens. Buckets larger than `maxBucketSize` are split by the first 3
       characters of the other field.
    3. compare in parallel with a `TaskGroup`. Each pair is compared only in its
       first shared bucket.
    4. group with union-find, then the anchor split: each subgroup is the member
       with the highest degree plus its direct neighbours.

    It returns `[DuplicateGroup]` (trackIDs with the anchor first, confidence,
    `[MatchReason]`). `match(a, b)` compares two tracks directly.
- `Selection/`:
  - `KeeperSelector`: `KeeperRule` ranks candidates in order and ties go to the
    earlier track. `autoSelect` returns the IDs to remove.
  - `RemovalPlanner`: plans the Bin or a mirrored move (root folders with the
    same name get "Music 2"), plus `uniqueDestination` ("x 2.mp3").
  - `RemovalExecutor`: works through the `FileMover` protocol.
    `LocalFileMover` is macOS-only (`#if os(macOS)`). Undo refuses to
    overwrite.
  - `RemovalLog`: stored as JSON. Has `lastUndoable` and `markUndone`.
- Tests (Swift Testing) are in `Tests/DedupCoreTests`, one file per area. They
  include a 50k synthetic scale test.

## Known risk areas to check when compiling

- Swift Testing parameterised tests with tuple arguments, including nested
  tuples in `CreditParserTests.splitsFeatured`.
- `KeeperRule.rank` is a switch expression that mixes `Double` and `Double?`
  branches.
- `NSLock.withLock` in `FakeFileMover`.
- Duration tolerance boundaries, and the anchor-grouping expectations in
  `MatchEngineTests.anchorCheckBreaksChains` and `trackNumberConstraint`. A
  chain a–b–c–d gives {a, b, c}, and d is dropped.

## Next: phase 4 (app shell)

- `project.yml`:
  - a macOS 15 app target `Deduplicator` with sources in `App/`
  - a dependency on the local `DedupCore` package
  - TagLib, either via SwiftPM or vendored and built from source, reached
    through an Objective-C++ or C shim (read all properties and tags, plus
    write for phase 8)
  - add `Deduplicator.xcodeproj/` stays gitignored
- Scanner:
  - recursive enumeration of `AudioFormat.supportedExtensions`
  - a bounded `TaskGroup` that reads tags and audio properties (TagLib) and
    decoded duration (`AVAudioFile`), and resolves `.m4a` to AAC or ALAC from
    the codec
  - a scan cache (path, size and mtime → `Track`) in Application Support, with
    progress and cancel
- Then phases 5–9, as listed in `docs/ROADMAP.md`.
