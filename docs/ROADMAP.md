# Roadmap

Draft. It will be firmed up once the open questions in `SPEC.md` are resolved.

| Phase | Deliverable | Verifiable in the cloud (Linux)? |
|-------|-------------|----------------------------------|
| 0 | Repo scaffolding, CLAUDE.md, spec | ✅ |
| 1 | `DedupCore`: `Track` model, normalisation rules, similarity metrics, with tests | ✅ `swift test` |
| 2 | `DedupCore`: match criteria, blocking, union-find grouping, confidence, auto-select rules, with tests | ✅ |
| 3 | App shell: SwiftPM/Xcode app target, folder picker, concurrent scanner, tag reader, decoded duration | ❌ needs a Mac |
| 4 | Results UI: group list, detail table, dynamic tag columns, diff highlighting | ❌ |
| 5 | Player: A/B playback at the same position | ❌ |
| 6 | Removal: Bin or folder, confirm sheet, log, undo | ❌ |
| 7 | Settings persistence, presets, keyboard shortcuts, polish, app icon | ❌ |
| 8 | Optional: audio fingerprinting, scan cache | partly |
