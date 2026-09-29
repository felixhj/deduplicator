# Deduplicator

A Mac app that finds duplicate music files by comparing their tags, not their
bytes, so it catches the copies that hash and file name checks miss. Listen to
the copies side by side, keep the best one, and move the rest to the Bin.

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

## Features

- **Tag-aware matching** on title and artist. Each field can require an
  identical, similar or fuzzy match, with an adjustable threshold. Start from a
  preset, and save your own.
- **Normalisation rules** that you can switch on or off one at a time:
  bracketed or suffix mix names, `feat.`/`ft.`/`featuring`/`vs.`/`&`/`x`
  artist credits, case, accents, punctuation, "The" prefixes, whitespace,
  track-number prefixes left in titles, and more.
- **Extra constraints:** duration tolerance in ±seconds, taken from the decoded
  audio rather than the length tag; same or different track number; and more.
- **A grouped results table** with columns you can resize, reorder and hide.
  Any tag in your files can be a column, and values that differ between copies
  are highlighted.
- **A built-in player** for A/B listening: switching to another copy of the
  same track carries on from the same point, and a waveform shows where you are.
- **Choosing the copy to keep:** by hand, or with auto-select rules such as
  lossless first, then the highest bitrate, with a preview before anything is
  marked.
- **Tag copying:** take tag values from one copy and write them to the one you
  keep, after reviewing every change.
- **Safe removal:** marked files go to the Bin, or to a folder you choose with
  their folders mirrored. Nothing is deleted, every removal is logged, and the
  last one can be undone, even after quitting.
- Built for libraries of **50,000+ tracks**, in MP3, AAC, ALAC, FLAC, AIFF and
  WAV.

## Install

1. Download `Deduplicator-<version>.zip` from the
   [latest release](https://github.com/felixhj/deduplicator/releases/latest),
   and unzip it.
2. Move Deduplicator into your Applications folder.
3. Open it. The app isn't notarised by Apple, so the first time, macOS says it
   can't check it and won't open it. Open System Settings > Privacy & Security,
   and under Security click **Open Anyway**. You only do this once.

Deduplicator needs macOS 15 (Sequoia) or later, on an Apple silicon or Intel
Mac. When a new version is out, the app says so as it opens. Help >
Deduplicator Help explains how to use it.

## Building from source

You need Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
xcodegen && open Deduplicator.xcodeproj   # then ⌘R to run, and ⌘U to run every test
scripts/test.sh                           # the package's tests, even with only the Command Line Tools
scripts/build-release.sh                  # a release build for Apple silicon and Intel, zipped for GitHub
```

`xcodegen` makes `Deduplicator.xcodeproj` from `project.yml`; the project file
isn't committed. [`CLAUDE.md`](CLAUDE.md) describes the architecture, and
[`docs/`](docs) holds the spec, the build history, and a checklist for testing
by hand.

## Project layout

```
project.yml              XcodeGen spec for the macOS app
Package.swift            SwiftPM manifest: DedupCore, DedupScanner and CTagLib
Sources/DedupCore/       Platform-independent logic: normalisation, similarity,
                         grouping, keeper rules and removal plans.
Sources/DedupScanner/    Folder scanning: finds audio files, reads tags with
                         TagLib, measures decoded duration, keeps the scan cache,
                         and draws the player's waveforms.
Sources/CTagLib/         TagLib, vendored as source, with a small C interface.
App/                     The macOS app: interface, player, removal and tag copying.
AppTests/                Tests hosted in the app.
Tests/                   Tests for DedupCore and DedupScanner.
scripts/                 Test, check and release scripts.
docs/                    Spec, roadmap, testing checklist and handoff notes.
```

## Licence

MIT: see [`LICENSE`](LICENSE). The app includes TagLib, available under the LGPL
2.1 or the MPL 1.1, and utfcpp, under the Boost Software License. Their licences
are in [`Sources/CTagLib/licenses/`](Sources/CTagLib/licenses).
