import DedupCore
import Foundation
import Testing
@testable import DedupScanner

struct ScanCacheTests {
    func file(_ path: String, size: Int64 = 100, modified: TimeInterval = 1_000) -> DiscoveredFile {
        DiscoveredFile(url: URL(filePath: path), root: URL(filePath: "/Music"), size: size, modified: Date(timeIntervalSince1970: modified))
    }

    func track(_ title: String, for file: DiscoveredFile) -> Track {
        Track(id: 0, url: file.url, title: title, fileSize: file.size, modified: file.modified, tags: ["TITLE": title])
    }

    @Test func hitOnlyWhenSizeAndDateMatch() {
        let original = file("/Music/a.mp3")
        var cache = ScanCache()
        cache.insert(track("A", for: original), for: original)

        #expect(cache.track(for: original)?.title == "A")
        #expect(cache.track(for: file("/Music/a.mp3", size: 101)) == nil)
        #expect(cache.track(for: file("/Music/a.mp3", modified: 1_001)) == nil)
        #expect(cache.track(for: file("/Music/b.mp3")) == nil)
    }

    @Test func roundTripsThroughDisk() async throws {
        try await withTemporaryFolder { folder in
            let url = folder.appending(path: "Nested/ScanCache.json")
            let a = file("/Music/Café/a.mp3", modified: 1_234.567_891)
            var cache = ScanCache()
            cache.insert(track("Café", for: a), for: a)
            try cache.save(to: url)

            let loaded = ScanCache.load(from: url)
            #expect(loaded.count == 1)
            #expect(loaded.track(for: a) == track("Café", for: a))
        }
    }

    @Test func missingCorruptOrOldCachesLoadEmpty() async throws {
        try await withTemporaryFolder { folder in
            #expect(ScanCache.load(from: folder.appending(path: "none.json")).count == 0)

            let corrupt = try folder.appending(path: "corrupt.json").create("{ not json")
            #expect(ScanCache.load(from: corrupt).count == 0)

            let old = try folder.appending(path: "old.json").create(#"{"version": 0, "entries": {}}"#)
            #expect(ScanCache.load(from: old).count == 0)
        }
    }

    @Test func removeMissingOnlyTouchesScannedRoots() {
        let kept = file("/Music/kept.mp3")
        let gone = file("/Music/Sub/gone.mp3")
        let elsewhere = file("/Other/x.mp3")
        let similarName = file("/Musical/y.mp3")
        var cache = ScanCache()
        for f in [kept, gone, elsewhere, similarName] { cache.insert(track("t", for: f), for: f) }

        cache.removeMissing(under: [URL(filePath: "/Music")], found: [kept.path])
        #expect(Set(cache.entries.keys) == [kept.path, elsewhere.path, similarName.path])
    }

    @Test func fiftyThousandEntriesRoundTrip() async throws {
        try await withTemporaryFolder { folder in
            var cache = ScanCache()
            for i in 0..<50_000 {
                let f = file("/Music/Artist \(i % 500)/Album \(i % 50)/\(i) Track.flac", modified: Double(i))
                var t = track("Track \(i)", for: f)
                t.artist = "Artist \(i % 500)"
                t.duration = 300
                t.tags = ["TITLE": t.title, "ARTIST": t.artist, "ALBUM": "Album", "GENRE": "House", "BPM": "124", "INITIALKEY": "8A"]
                cache.insert(t, for: f)
            }
            let url = folder.appending(path: "ScanCache.json")
            let clock = ContinuousClock()
            let saving = try clock.measure { try cache.save(to: url) }
            var loaded = ScanCache()
            let loading = clock.measure { loaded = ScanCache.load(from: url) }
            #expect(loaded.count == 50_000)
            // Generous bounds: these catch a pathological slowdown, not small regressions.
            #expect(saving < .seconds(20))
            #expect(loading < .seconds(20))
        }
    }
}
