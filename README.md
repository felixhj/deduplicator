# Deduplicator

A native macOS app for finding and removing duplicate music files, by comparing
tags intelligently instead of by file hash.

> **Status:** pre-alpha. The v1 scope is agreed. See [`docs/SPEC.md`](docs/SPEC.md)
> for requirements and [`docs/ROADMAP.md`](docs/ROADMAP.md) for build phases.

## Why

Plain hash or filename checks miss most real-world duplicates in DJ and
collector libraries. The same track often turns up as:

| Copy A                         | Copy B                                        |
| ------------------------------ | --------------------------------------------- |
| `Strings of Life`              | `Strings of Life (Original Mix)`              |
| `Rhythim Is Rhythim`           | `Rhythim Is Rhythim ft. Derrick May`          |
| `Café Del Mar - Energy 52`     | `Cafe del Mar – Energy52`                     |

A plain fuzzy matcher scores these as very different, sometimes under 50%
similar. Deduplicator normalises tags first: it strips mix and version
suffixes, pulls featured artists out, folds accents and punctuation, and so on.
Then it compares the cleaned values, with a matching strictness you choose for
each field.

## Features (planned)

- **Tag-aware matching** on title and artist. Each field can require an
  identical, similar or fuzzy match, with an adjustable threshold.
- **Smart normalisation rules** that you can switch on or off one at a time:
  bracketed or suffix mix names, `feat.`/`ft.`/`featuring`/`vs.`/`&`/`x`
  artist credits, case, accents, punctuation, "The" prefixes, whitespace,
  track-number prefixes left in titles, and more.
- **Extra constraints:** duration tolerance in ±seconds, taken from the decoded
  audio rather than the length tag; same or different track number; and more.
- **Grouped results view** that shows each duplicate group with configurable,
  resizable and reorderable columns. Any tag in the file can be a column.
- **Built-in player** for A/B listening within a group.
- **Choosing the copy to keep:** pick by hand or with auto-select rules, such
  as highest bitrate, lossless over lossy, or longest.
- **Waveform view** in the player.
- **Basic tag copying:** take tag values from one copy and write them to the
  keeper.
- **Safe removal:** send the selected files to the Bin, or move them to a folder
  you choose, with the folder structure mirrored. Every removal is logged and
  can be undone.
- Built for libraries of **50k+ tracks**.

## Requirements

- macOS 15 (Sequoia) or later
- Xcode 16+ and Swift 6 to build the app. The Swift package builds and tests
  with just the Command Line Tools.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Building

```sh
swift build
scripts/test.sh    # runs `swift test`; also works with only the Command Line Tools
xcodegen           # generates Deduplicator.xcodeproj, which isn't committed
open Deduplicator.xcodeproj
```

## Project layout

```
project.yml              XcodeGen spec for the macOS app
Package.swift            SwiftPM manifest: DedupCore, DedupScanner and CTagLib
Sources/DedupCore/       Platform-independent matching engine (normalisation,
                         similarity, grouping, removal plans). Builds on Linux too.
Sources/DedupScanner/    Folder scanning: finds audio files, reads tags with
                         TagLib, measures decoded duration, keeps the scan cache.
Sources/CTagLib/         TagLib, vendored as source, with a small C interface.
App/                     macOS SwiftUI app: UI, player and file operations.
Tests/                   Tests for DedupCore and DedupScanner.
scripts/                 Test and build helpers.
docs/                    Spec, roadmap and design notes.
```

## Licence

TBD. The vendored TagLib is available under the LGPL 2.1 or the MPL 1.1, and
utfcpp under the Boost Software License. See `Sources/CTagLib/licenses/`.
