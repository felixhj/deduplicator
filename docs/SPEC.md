# Deduplicator — Product Spec

Status: **agreed v1 scope** (planning round 1, 2026-09-29). Items marked ⏳ are deferred to after v1.

## 1. Goal

Given one or more folders of music files, find groups of files that are the
same recording, show them side by side with their tags and a player, let the
user choose which copies to remove, and remove them safely.

## 2. Input

- The user adds one or more root folders, which are scanned recursively. Only
  folders are supported: there is no Music.app, Swinsian or Rekordbox import in v1.
- Supported formats: MP3, AAC/M4A, ALAC, FLAC, AIFF, WAV. Tags are read with
  **TagLib**, because AVFoundation handles FLAC and arbitrary ID3 frames
  poorly. Decoding and playback use AVFoundation, which supports all of these
  on macOS 15.
- For each file the app reads:
  - **all tags** present, so any tag can be shown as a column
  - **decoded duration** from the audio stream. The TLEN/length tag is never
    used.
  - file info: path, size, format/codec, bitrate, sample rate, bit depth,
    channels, date modified
- Scan results are cached, keyed by path, size and mtime, so rescans are fast.
  This is required, because the target is **50k+ tracks**. The cache is
  `~/Library/Application Support/Deduplicator/ScanCache.json`. Entries for
  files that have gone are dropped. Files that had problems aren't cached, so
  they're read again next time.
- Tags use TagLib's unified names (`TITLE`, `ARTIST`, `INITIALKEY`, …), so a
  tag lines up across formats: an MP3's `TKEY` frame and a FLAC's `INITIALKEY`
  comment are both `INITIALKEY`. A tag with several values shows them joined
  with "; ".
- Scanning skips hidden files (including "._" files), the contents of packages
  such as Logic projects, and symbolic links to files, so a linked file isn't
  matched with itself. A chosen folder that is itself a symbolic link is
  followed. A folder inside another chosen folder, or the same folder chosen
  twice by different paths, is only scanned once.
- A file whose tags or audio can't be read is still listed, so the filename
  fallback can match it, and the scan reports the problem.

## 3. Matching

### 3.1 Normalisation pipeline

Before comparison, each field goes through an ordered list of rules. Every
rule can be switched on or off in the UI, and every rule is unit-tested.

**Default: every stripping rule is OFF.** The user turns on the ones they
want. Basic folding (case, whitespace) is on by default only at the *Same*
level and above. Presets such as "DJ library" can switch on a sensible set in
one click.

**Title rules**
| Rule | Example |
|------|---------|
| Strip mix/version suffix in brackets | `Song (Original Mix)` → `Song`; also `[Extended]`, `{Radio Edit}` |
| Strip dash-suffixed versions | `Song - Radio Edit` → `Song` |
| Strip featured artist from title | `Song (feat. X)` → `Song` (and add X to the artist set) |
| Strip leading track numbers | `01 - Song`, `01. Song` → `Song` |
| Strip "remastered" / year noise | `Song (2011 Remaster)` → `Song` |

**Artist rules**
| Rule | Example |
|------|---------|
| Split featured artists | `A ft. B`, `A feat. B`, `A featuring B`, `A (feat. B)` → primary `A`, featured `{B}` |
| Split collaborations | `A & B`, `A x B`, `A vs. B`, `A, B`, `A and B` → set `{A, B}` |
| Strip "The" prefix | `The Prodigy` = `Prodigy` |

**Both fields**
| Rule | Example |
|------|---------|
| Case fold | `SONG` = `song` |
| Diacritic fold | `Café` = `Cafe` |
| Punctuation and symbol fold | `–`/`—`/`-`, curly/straight quotes, `&` ↔ `and` |
| Whitespace collapse | `Energy  52` = `Energy 52` |
| Optional: ignore all spaces | `Energy52` = `Energy 52` |

**Mix-name awareness (important).** Stripping `(Original Mix)` is right, but
stripping `(Carl Craig Remix)` would merge *different recordings*. The bracket
stripper therefore uses classes:

- *Neutral* versions, stripped when the rule is on: Original Mix, Extended Mix, Radio
  Edit, Album Version, Remastered, Explicit/Clean, Mono/Stereo, …
- *Distinct* versions, kept unless the next setting is on: anything with Remix, Dub, VIP, Rework,
  Edit by a named person, Live, Acoustic, Instrumental, …
- A user setting: **"Treat all versions as the same track"**, which strips
  everything.

### 3.2 Comparison per field

Title and artist each get a strictness level (a Swinsian-style model):

| Level | Meaning |
|-------|---------|
| Identical | raw strings equal, with no normalisation |
| Same | normalised strings equal |
| Similar | normalised similarity ≥ threshold (default 90%) |
| Fuzzy | normalised similarity ≥ lower threshold (default 75%), token-order-insensitive |
| Ignore | field isn't compared |

Similarity uses the maximum of Jaro-Winkler and a token-set ratio, so word
order (`Energy 52 – Cafe del Mar` vs `Cafe del Mar – Energy 52`) and extra
words matter less.

Artist comparison is **set-aware**: primary artists must match. When the
"split featured artists" rule is on, featured artists are ignored; otherwise
they're part of the compared string.

The user can also add extra fields (album, album artist, year, …) as match
criteria, with the same levels.

### 3.3 Constraints

- **Duration:** within ±N seconds (slider from 0 to 30 s, default 3 s), from the
  decoded audio. It can be switched off.
- **Track number:** any / must be same / must be different.
- **Album:** any / must be same / must be different. "Different" is useful for
  finding cross-album duplicates such as compilations.
- **Format:** any / only compare across formats (for example, find the MP3
  copies of FLACs).

### 3.4 Other smart methods (proposed)

1. **Blocking for speed:** candidate pairs are only generated within buckets
   keyed on a normalised artist or title prefix, so 50k-track libraries don't
   need about 1.25 billion comparisons.
2. **Swapped fields:** detect title and artist written the wrong way round
   (`Artist: Strings of Life, Title: Derrick May`).
3. **Artist in title:** handle a title of `Derrick May - Strings of Life` with
   the artist tag empty or equal to the artist.
4. **Filename fallback:** when tags are missing, parse `Artist - Title.ext`
   from the filename (opt-in).
5. **Confidence score:** each group gets a score and a list of the rules that
   fired, so the user can see *why* the tracks matched.
6. ⏳ **Audio fingerprint (after v1):** a Chromaprint-style fingerprint to
   confirm or find matches with junk tags.

### 3.5 Grouping

Pairwise matches are merged with union-find into groups. To stop a chain
A≈B≈C from grouping A with a very different C, each group is checked so that
every member matches the group's anchor (configurable).

## 4. Results UI

- **One flat, banded table** (like Swinsian): every file in every duplicate
  group, with groups separated by a group header row and alternating band
  colours. Groups can be collapsed by clicking the header or its disclosure
  button; Option-click collapses or expands every group. The group header shows
  the file count, the confidence and why the tracks matched, and warns when
  every copy is marked for removal.
- Columns:
  - default columns: ✓ (remove), ▶, track #, title, artist, album artist,
    album, year, comment, duration, bitrate, format, size, path. More built-in
    columns: genre, disc, sample rate, bit depth, channels, modified, file name.
  - ✓ and ▶ always come first. ▶ shows a speaker on the copy in the player,
    and a play button on the row under the pointer.
  - columns can be resized, reordered and hidden, and the layout persists
  - **any tag** found in the scanned files can be added as a column. The column
    picker (right-click the column headings, or the Columns toolbar menu) lists
    every tag key seen.
  - cells whose value differs from the rest of the group are highlighted: a
    cell is highlighted when its value isn't the group's single most common
    value. When no value is most common, as with two copies that disagree,
    every copy's cell is highlighted. Path and file name never are.
- Filtering by text (title, artist, album, album artist and path, ignoring case
  and accents) and by minimum confidence. A group shows when any copy matches.
- Sorting groups by confidence (the default), by number of copies, or by
  clicking a column heading, which also orders the copies within each group.
- Keyboard: ↑/↓ moves between rows, space plays or pauses, `k` keeps, `d` marks
  for deletion, and ⌘↓ and ⌘↑ go to the next and previous group. Double-clicking
  a row plays it. The right-click menu has Mark for Removal, Keep and Show in
  Finder.
- The match settings sit in an inspector beside the table, starting from the
  Standard, DJ Library or Loose preset. Changes apply as you make them, after a
  short pause.
- A new scan clears the marks. Changing match settings drops marks on copies
  that are no longer in any group, so a copy can't stay marked where it can't
  be seen. Marks in groups hidden by the filter stay.

## 5. Player

- The player sits under the table. It shows the copy in it (the track, then
  the format, bitrate and file name that tell copies apart), play and pause,
  the position and duration, and Show in Finder.
- The **waveform** is the scrubber: the part already played is in the accent
  colour, and clicking or dragging moves the position. It shows the peak and
  the average level (root mean square) of 1,000 equal slices of the decoded
  audio. It's drawn in the background and cached in
  `~/Library/Caches/Deduplicator/Waveforms`, keyed by path, size and mtime.
  After a copy's waveform, the other copies' in its group are drawn too, so
  switching to one shows its waveform at once.
- The player follows the table: a copy selected on its own goes into the
  player. Several selected copies leave it alone, so selecting copies to mark
  them doesn't interrupt the one playing.
- While a copy plays, selecting another copy of the same track switches to it
  **at the same position**, for quick A/B comparison. Settings (Player) can
  switch this off. Selecting a copy of another track plays it from the start.
- Space plays or pauses. Double-clicking a row, or clicking its ▶ button, plays
  it. Playing to the end stops and goes back to the start.
- A copy that can't be played says why: its file has moved or been deleted
  since the scan, or Core Audio can't play it.
- Starting a scan empties the player. Closing the window pauses it.

## 6. Choosing keepers

- By hand: tick the files to delete. The app warns if every file in a group is
  ticked.
- **Auto-select** rules, applied in order and user-editable:
  prefer lossless → higher bitrate → higher sample rate → longer duration →
  more tags filled → path contains/doesn't contain X → oldest/newest file.
- "Auto-select all groups" with a preview of the result.

## 7. Basic tag editing

- In a group, the user can **copy chosen tag values from any copy to the
  keeper**. For example, keep the FLAC but take the MP3's better comment and
  year.
- Writes go through TagLib. They are only made to the file the user chose, and
  only after a confirmation that shows the before and after values.
- There is no free-form tag editor in v1.

## 8. Removal

- The user chooses what happens on **Remove** in Settings, and can change it
  in the confirm sheet:
  1. **Move to Bin** (`FileManager.trashItem`, so the files can be restored from
     the Bin)
  2. **Move to folder**: the user picks a destination, and the **folder
     structure is mirrored** relative to the scanned root. For example,
     `Root/A/B/x.mp3` goes to `Dest/<RootName>/A/B/x.mp3`.
- A confirm sheet shows the file count and total size.
- Every operation is appended to a JSON log (timestamp, original path,
  destination), stored in Application Support.
- **Undo last removal** moves the files back to their original paths. Undo
  from the Bin uses the destination URL that `trashItem` returns.
- Files are never permanently deleted by the app.

## 9. Platform and non-functional

- **macOS 15+**, for personal use: no App Sandbox and no App Store. The project
  is generated with **XcodeGen** from `project.yml`.
- Must stay responsive with **50k+ tracks**:
  - scanning is concurrent (a bounded task group), with progress and cancel
  - there is a persistent scan cache
  - matching uses blocking so the number of comparisons stays close to linear,
    and runs off the main thread with progress and cancel
  - the table is virtualised (SwiftUI `Table` or an `NSTableView` if needed)

## 10. Deferred (post-v1)

- ⏳ Audio fingerprinting
- ⏳ Importing from the Music.app, Swinsian or Rekordbox libraries
- ⏳ A full tag editor
