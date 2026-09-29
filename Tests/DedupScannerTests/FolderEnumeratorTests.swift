import Foundation
import Testing
@testable import DedupScanner

struct FolderEnumeratorTests {
    /// Resolves roots and finds files, as the scanner does.
    func find(_ roots: [URL], found: (Int) -> Void = { _ in }) throws -> (files: [DiscoveredFile], issues: [ScanIssue]) {
        let (scanRoots, rootIssues) = FolderEnumerator.scanRoots(roots)
        let (files, issues) = try FolderEnumerator.audioFiles(in: scanRoots, found: found)
        return (files, rootIssues + issues)
    }

    @Test(arguments: [
        ("/Music/a.mp3", "/Music", true),
        ("/Music", "/Music", true),
        ("/Music/Sub/b.mp3", "/Music/", true),
        ("/Musical/a.mp3", "/Music", false),
        ("/Mus", "/Music", false),
        ("/anything", "/", true),
    ])
    func contains(path: String, folder: String, expected: Bool) {
        #expect(FolderEnumerator.contains(URL(filePath: folder), URL(filePath: path)) == expected)
    }

    @Test func filePathIgnoresTrailingSlashAndEncoding() {
        #expect(URL(filePath: "/Music/", directoryHint: .isDirectory).filePath == "/Music")
        #expect(URL(filePath: "/Music/Café Del Mar.mp3").filePath == "/Music/Café Del Mar.mp3")
        #expect(URL(filePath: "/").filePath == "/")
    }

    @Test(arguments: [
        ("/private/var/Music/a.mp3", "/var/Music", "/private/var/Music", "/var/Music/a.mp3"),
        ("/Volumes/Disk/Music/A/b.mp3", "/Users/me/Music", "/Volumes/Disk/Music", "/Users/me/Music/A/b.mp3"),
        ("/x/a.mp3", "/link", "/", "/link/x/a.mp3"),
        ("/x/a.mp3", "/", "/", "/x/a.mp3"),
        ("/elsewhere/a.mp3", "/Music", "/Music", "/elsewhere/a.mp3"),
    ])
    func userURLSwapsRealPathForChosenFolder(found: String, chosen: String, real: String, expected: String) {
        let root = ScanRoot(url: URL(filePath: chosen), realPath: real)
        #expect(FolderEnumerator.userURL(for: URL(filePath: found), in: root).filePath == expected)
    }

    @Test func scanRootsDropsNestedDuplicateAndMissingFolders() async throws {
        try await withTemporaryFolder { folder in
            let music = folder.appending(path: "Music")
            let musical = folder.appending(path: "Musical")
            for url in [music.appending(path: "House"), musical] {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            let missing = folder.appending(path: "Gone")
            let (roots, issues) = FolderEnumerator.scanRoots([music.appending(path: "House"), music, music, musical, missing])
            #expect(roots.map(\.url.lastPathComponent).sorted() == ["Music", "Musical"])
            #expect(issues.map(\.url) == [missing.standardizedFileURL])
        }
    }

    @Test func findsSupportedFilesSortedByPath() async throws {
        try await withTemporaryFolder { folder in
            try folder.appending(path: "b.flac").create()
            try folder.appending(path: "Sub/a.MP3").create()
            try folder.appending(path: "Sub/Deeper/c.m4a").create()
            try folder.appending(path: "notes.txt").create()
            try folder.appending(path: "cover.jpg").create()

            let (files, issues) = try find([folder])
            #expect(issues.isEmpty)
            let relative = files.map { String($0.path.dropFirst(folder.filePath.count + 1)) }
            #expect(relative == ["Sub/Deeper/c.m4a", "Sub/a.MP3", "b.flac"])
            #expect(files.allSatisfy { $0.root == folder.standardizedFileURL })
            #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        }
    }

    @Test func recordsSizeAndModificationDate() async throws {
        try await withTemporaryFolder { folder in
            let url = try folder.appending(path: "a.mp3").create("12345")
            let date = Date(timeIntervalSince1970: 1_500_000_000)
            try url.setModified(date)

            let (files, _) = try find([folder])
            #expect(files.first?.size == 5)
            #expect(files.first?.modified == date)
        }
    }

    @Test func skipsHiddenAppleDoubleAndLinkedFiles() async throws {
        try await withTemporaryFolder { folder in
            let real = try folder.appending(path: "real.mp3").create()
            try folder.appending(path: ".hidden.mp3").create()
            try folder.appending(path: "._real.mp3").create()
            try folder.appending(path: ".Hidden Folder/inside.mp3").create()
            try FileManager.default.createSymbolicLink(at: folder.appending(path: "link.mp3"), withDestinationURL: real)

            let (files, _) = try find([folder])
            #expect(files.map(\.url.lastPathComponent) == ["real.mp3"])
        }
    }

    #if os(macOS)
    @Test func skipsPackageContents() async throws {
        try await withTemporaryFolder { folder in
            try folder.appending(path: "Tool.app/Contents/Resources/sound.wav").create()
            try folder.appending(path: "song.wav").create()

            let (files, _) = try find([folder])
            #expect(files.map(\.url.lastPathComponent) == ["song.wav"])
        }
    }
    #endif

    @Test func followsARootThatIsASymbolicLink() async throws {
        try await withTemporaryFolder { folder in
            let real = folder.appending(path: "Drive/Music")
            try real.appending(path: "Sub/a.mp3").create()
            let link = folder.appending(path: "Music Link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

            let (files, issues) = try find([link])
            #expect(issues.isEmpty)
            #expect(files.map(\.path) == [link.filePath + "/Sub/a.mp3"])
            #expect(files.first?.root == link.standardizedFileURL)
        }
    }

    @Test func sameFolderThroughALinkIsScannedOnce() async throws {
        try await withTemporaryFolder { folder in
            let real = folder.appending(path: "Music")
            try real.appending(path: "a.mp3").create()
            let link = folder.appending(path: "Music Link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

            let (files, _) = try find([real, link])
            #expect(files.count == 1)
        }
    }

    @Test func nestedRootsFindEachFileOnce() async throws {
        try await withTemporaryFolder { folder in
            try folder.appending(path: "Sub/a.mp3").create()
            let (files, _) = try find([folder.appending(path: "Sub"), folder])
            #expect(files.count == 1)
            #expect(files.first?.root == folder.standardizedFileURL)
        }
    }

    @Test func reportsRunningCount() async throws {
        try await withTemporaryFolder { folder in
            for name in ["a", "b", "c"] { try folder.appending(path: "\(name).mp3").create() }
            var counts: [Int] = []
            _ = try find([folder]) { counts.append($0) }
            #expect(counts == [1, 2, 3])
        }
    }
}
