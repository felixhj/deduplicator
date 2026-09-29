import DedupCore
import Foundation

/// An audio file found while scanning, with the file info the cache checks.
public struct DiscoveredFile: Sendable, Hashable {
    public let url: URL
    /// The folder the user added that this file was found under.
    public let root: URL
    public let size: Int64
    public let modified: Date
    /// `url.filePath`, worked out once because sorting and the cache use it a lot.
    let path: String

    public init(url: URL, root: URL, size: Int64, modified: Date) {
        self.url = url
        self.root = root
        self.size = size
        self.modified = modified
        path = url.filePath
    }
}

/// Something that went wrong with one file or folder. The rest of the scan carries on.
public struct ScanIssue: Sendable, Hashable {
    public var url: URL
    public var message: String

    public init(url: URL, message: String) {
        self.url = url
        self.message = message
    }
}

/// A folder to scan: the URL the user chose, and its real path with symbolic
/// links resolved.
struct ScanRoot: Hashable {
    var url: URL
    var realPath: String
}

enum FolderEnumerator {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
    ]

    /// Resolves each folder's real path. Drops missing folders (as issues) and
    /// folders that are the same as, or inside, another one, so no file is
    /// found twice. Two paths to one folder through a symbolic link count as the same.
    static func scanRoots(_ urls: [URL]) -> (roots: [ScanRoot], issues: [ScanIssue]) {
        var resolved: [ScanRoot] = []
        var issues: [ScanIssue] = []
        for url in urls.map(\.standardizedFileURL) {
            guard let realPath = realPath(of: url), isDirectory(realPath) else {
                issues.append(ScanIssue(url: url, message: "The folder couldn't be found."))
                continue
            }
            resolved.append(ScanRoot(url: url, realPath: realPath))
        }
        var kept: [ScanRoot] = []
        for root in resolved.sorted(by: { $0.realPath.count < $1.realPath.count })
        where !kept.contains(where: { isPath(root.realPath, inFolder: $0.realPath) }) {
            kept.append(root)
        }
        return (kept, issues)
    }

    /// Whether `url` is `folder` itself or somewhere inside it.
    static func contains(_ folder: URL, _ url: URL) -> Bool {
        isPath(url.standardizedFileURL.filePath, inFolder: folder.standardizedFileURL.filePath)
    }

    /// The same check on paths as `URL.filePath` gives them.
    static func isPath(_ path: String, inFolder folder: String) -> Bool {
        path == folder || path.hasPrefix(folder == "/" ? "/" : folder + "/")
    }

    /// Finds files with a supported extension under each root, sorted by path.
    /// Skips hidden files (including "._" AppleDouble files), the contents of
    /// packages such as Logic projects, and symbolic links, so a linked file
    /// isn't counted as a duplicate of itself. `found` gets the running count.
    ///
    /// The enumerator is given each root's real path, because it doesn't follow
    /// a root that is itself a symbolic link. File URLs are then rebuilt under
    /// the URL the user chose, so they always start with `DiscoveredFile.root`.
    static func audioFiles(in roots: [ScanRoot], found: (Int) -> Void) throws -> (files: [DiscoveredFile], issues: [ScanIssue]) {
        var files: [DiscoveredFile] = []
        var issues: [ScanIssue] = []
        for root in roots {
            // The enumerator reports errors through this closure, on this thread.
            var folderIssues: [ScanIssue] = []
            let enumerator = FileManager.default.enumerator(
                at: URL(filePath: root.realPath, directoryHint: .isDirectory),
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, error in
                    folderIssues.append(ScanIssue(url: url, message: "Couldn't read this: \(error.localizedDescription)"))
                    return true
                }
            )
            while let url = enumerator?.nextObject() as? URL {
                if files.count.isMultiple(of: 256) { try Task.checkCancellation() }
                guard let file = audioFile(at: url, root: root) else { continue }
                files.append(file)
                found(files.count)
            }
            issues += folderIssues
        }
        files.sort { $0.path < $1.path }
        return (files, issues)
    }

    private static func audioFile(at url: URL, root: ScanRoot) -> DiscoveredFile? {
        guard AudioFormat.supportedExtensions.contains(url.pathExtension.lowercased()),
              let values = try? url.resourceValues(forKeys: resourceKeys),
              values.isRegularFile == true, values.isSymbolicLink != true
        else { return nil }
        return DiscoveredFile(
            url: userURL(for: url, in: root),
            root: root.url,
            size: Int64(values.fileSize ?? 0),
            modified: values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
        )
    }

    /// Swaps the root's real path at the start of `url` for the URL the user chose.
    static func userURL(for url: URL, in root: ScanRoot) -> URL {
        let path = url.filePath
        guard isPath(path, inFolder: root.realPath) else { return url }
        let relative = path.dropFirst(root.realPath == "/" ? 0 : root.realPath.count)
        let base = root.url.filePath == "/" ? "" : root.url.filePath
        return URL(filePath: base + relative)
    }

    private static func realPath(of url: URL) -> String? {
        guard let resolved = realpath(url.filePath, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

extension URL {
    /// The file system path without percent encoding or a trailing slash, so
    /// a folder's path is the same however its URL was made.
    var filePath: String {
        let path = path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
