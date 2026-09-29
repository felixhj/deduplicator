# Testing by hand

The automated tests (`scripts/test.sh`, and ⌘U in Xcode) check the logic,
the models and the table, with generated files. They can't listen, click,
drag or judge whether the results make sense for a real library. This list
covers that. Work through it before calling v1 done, and add to it when a
feature changes.

Tick items as they pass, and note anything odd next to them.

## Before you start

- [ ] Make a test library by **copying** some music to a scratch folder. Never
      test removal or tag writing on your only copy.
- [ ] Include known duplicates in several formats: MP3, AAC and ALAC (both
      `.m4a`), FLAC, AIFF and WAV.
- [ ] Include some awkward files: untagged ones, titles with `(Original Mix)`,
      remixes of the same track, `feat.` credits, track numbers left in titles,
      artist and title swapped, a long DJ mix, a 24-bit/96 kHz file, a file
      that isn't really audio, and names with accents.
- [ ] Put part of the library on an external drive.
- [ ] Build: `xcodegen && open Deduplicator.xcodeproj`, then ⌘R. Debug builds
      are slower, so judge speed in a Release build (Product > Scheme > Edit
      Scheme > Run > Build Configuration > Release).

Where the app keeps its data, to inspect it or start again:

| What | Where |
|------|-------|
| Settings, folders, columns | `defaults read io.github.felixhj.Deduplicator` (delete with `defaults delete io.github.felixhj.Deduplicator`) |
| Scan cache | `~/Library/Application Support/Deduplicator/ScanCache.json` |
| Removal log | `~/Library/Application Support/Deduplicator/RemovalLog.json` |
| Waveforms | `~/Library/Caches/Deduplicator/Waveforms/` |

## Folders and scanning

- [ ] Add folders with the + button, with File > Add Folder… (⌘O), and by
      dragging from the Finder. Adding one twice does nothing.
- [ ] Remove a folder with the − button and with the Delete key.
- [ ] Folders you add are still there after quitting and reopening.
- [ ] A folder in Desktop, Documents, Downloads or on an external drive asks
      for permission once; after Allow, the scan finds its files.
- [ ] A scan shows progress, and Stop (⌘.) stops it and goes back to what was
      there before.
- [ ] Scan a second time: much faster, and the scan report says most tracks
      came from the scan cache.
- [ ] The scan report (status bar) lists files with problems, such as the file
      that isn't audio, with a reason each.
- [ ] Durations in the table match what Music or QuickTime says, give or take
      a second, including for VBR MP3s.
- [ ] A folder added through a symbolic link, and a folder inside another
      chosen folder, don't make any file appear twice.

## Matching

- [ ] The groups look right with the Standard preset: real duplicates grouped,
      different songs apart.
- [ ] A remix isn't grouped with the original unless "Strip all versions" is
      on. An `(Original Mix)` copy is grouped with the plain one under the DJ
      Library preset.
- [ ] Each match setting changes the groups, after a short pause, while you
      change it.
- [ ] Each group header's confidence and reasons make sense.
- [ ] Settings are kept after quitting and reopening. Restore Standard
      Settings puts them back.

## Results table

- [ ] Groups are banded, and each header shows the copies, confidence and
      reasons.
- [ ] Clicking a header or its triangle collapses and expands it;
      Option-click does every group.
- [ ] Add, move, resize and hide columns, from the header's right-click menu
      and the Columns toolbar menu. Any tag can be added. The layout is kept
      after quitting and reopening.
- [ ] Cells that differ within a group are highlighted; path and file name
      never are.
- [ ] Clicking a column heading sorts groups and the copies within them;
      clicking again reverses it.
- [ ] The filter matches title, artist, album, album artist and path,
      ignoring case and accents. The confidence menu hides weaker groups.
- [ ] Keys: ↑/↓ move, `d` marks, `k` keeps, ⌘↓ and ⌘↑ jump between groups.
- [ ] Right-click a copy: Mark for Removal, Keep and Show in Finder work.
- [ ] Marking every copy in a group shows the orange warning in its header.
- [ ] Light and dark mode both look right.

## Player

- [ ] Select a copy and press space: it plays. Space again pauses.
- [ ] Double-click a copy, or click the ▶ that appears under the pointer: it
      plays.
- [ ] While one copy plays, click another copy of the same track: it switches
      straight away, at the same point. Compare an MP3 and a FLAC this way.
- [ ] Turn off "Switch copies at the same position" in Settings: switching
      now starts from the top.
- [ ] Selecting a copy of another track while playing starts it from the top.
- [ ] Selecting several copies, to mark them, doesn't change what's playing.
- [ ] The waveform appears within a moment, and the group's other copies show
      theirs at once. A long DJ mix takes a few seconds.
- [ ] Click and drag on the waveform to move the position; the times update.
- [ ] Every format plays, including 24-bit/96 kHz.
- [ ] Rename or move a file in the Finder, then play it: the player says it
      has moved.
- [ ] Unplug headphones, or change the output device, while playing: playback
      carries on or stops cleanly, and the play button shows which.
- [ ] Close the window while playing: it stops. Starting a scan empties the
      player.
- [ ] Show in Finder (the folder button) selects the right file.

## Auto-select

- [ ] Auto-Select (toolbar or Edit menu) previews each group's keeper and what
      it marks, and the count and size.
- [ ] Add, remove and drag rules; the preview follows. Path rules and Prefer a
      format work. The rules are kept after quitting and reopening.
- [ ] Mark N Copies marks exactly what the preview said, and replaces marks
      you'd made in those groups.
- [ ] With a filter on, only the groups shown change.
- [ ] Unmark All (Edit menu) clears every mark.

## Removal and undo

Use the test copy of your music for all of these.

- [ ] Remove (toolbar, or ⌘⌫) shows the file count, size, and warnings when
      every copy in a group is marked or marks are hidden by the filter.
- [ ] Move to Bin: the files are in the Bin, and the Finder's Put Back works
      on them too.
- [ ] Move to a folder: the files are there, inside a folder named after the
      scanned folder, with the same subfolders. The sheet showed where the
      first would go.
- [ ] The sheet refuses a folder inside a scanned folder, and a scanned
      folder's parent.
- [ ] The removed copies leave the table; a group left with one copy goes.
- [ ] Removing a large batch shows progress, and Stop stops it part-way.
- [ ] A file you've locked in the Finder (Get Info > Locked) is listed as not
      moved, with a reason, and stays marked.
- [ ] Undo (status bar link, or File > Undo Removal of N Files) puts the files
      back, and they return to the table.
- [ ] Undo after quitting and reopening: the files go back, and the next scan
      shows them.
- [ ] Two removals, then undo twice: both are put back, newest first.
- [ ] `RemovalLog.json` lists each removal with its files, and when it was
      undone.
- [ ] Removing the copy that's in the player empties the player.
- [ ] Remove to the Bin from an external drive: the files go to that drive's
      Bin, and undo works.

## Copying tags

Use the test copy of your music for these too.

- [ ] Right-click a copy > Copy Tags from This Copy…, and select one copy then
      Edit > Copy Tags…: the sheet opens with that copy as From, and the copy
      you're keeping as To.
- [ ] Only tags that would change are listed. Gaps in tags such as date,
      comment and BPM are ticked; encoder, loudness and iTunes technical tags
      aren't.
- [ ] Changing From or To reads the files again and updates the list.
- [ ] Review shows each tag's value before and after; Back goes back; Write
      Tags writes them.
- [ ] Afterwards the table shows the new values (add the tag's column to
      see), another app such as Music or Mp3tag shows them in the file, and
      the file still plays.
- [ ] Write to each format in turn: MP3, AAC, ALAC, FLAC, AIFF and WAV.
- [ ] A tag with several values, such as two artists in a FLAC, arrives as
      several values.
- [ ] A locked file (Get Info > Locked) says it couldn't be written, and
      nothing changes.
- [ ] Writing to the copy in the player empties the player first.
- [ ] `TagEditLog.json` lists each write with the values before and after.

## Settings, shortcuts and polish

- [ ] The app icon looks right in the Dock, the Finder, the App Switcher (⌘⇥)
      and the About box, in light and dark mode, and with Tinted or Clear
      icons (System Settings > Appearance).
- [ ] Deduplicator > About Deduplicator shows the version and credits TagLib
      and utfcpp.
- [ ] Help > Keyboard Shortcuts (⌘?) lists the shortcuts, and each one works.
- [ ] ⌘F puts the cursor in the filter.
- [ ] View > Show Match Settings (⌥⌘I) shows and hides the match settings,
      and the menu item's name follows.
- [ ] ← and → in the table skip back and forward 10 seconds in the copy in
      the player.
- [ ] Save the match settings as a preset (the … button beside Preset),
      choose it again after changing settings, then delete it. Saved presets
      are kept after quitting and reopening. Saving under a taken name
      replaces that preset.
- [ ] The group order (the Order menu or a column heading) and the minimum
      confidence are kept after quitting and reopening; the filter text isn't.
- [ ] The window's size and position, the sidebar's width and whether the
      match settings show are kept after quitting and reopening.
- [ ] Quit (⌘Q) during a long removal: the app says it's changing files and
      stays open.
- [ ] Settings (⌘,) holds the removal and player settings, and both are kept.
- [ ] Every sheet can be cancelled with Escape, and its main button pressed
      with Return.

## A big library

- [ ] Scan your whole real library, 50,000 tracks or more, in a Release build:
      it finishes, the table scrolls smoothly, and filtering is quick.
- [ ] Changing a match setting finds duplicates again within a few seconds.
- [ ] Auto-select's preview keeps up as you change the rules.
- [ ] Memory use (Activity Monitor) stays reasonable.
