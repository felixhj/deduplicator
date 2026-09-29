import Foundation

/// What happens to files the user removes. Nothing is ever deleted permanently.
public enum RemovalMode: Sendable, Hashable, Codable {
    case moveToBin
    /// Move into this folder, mirroring each file's path under its scan root.
    case moveToFolder(URL)
}

public struct PlannedMove: Sendable, Hashable, Codable {
    public var trackID: Track.ID
    public var source: URL
    /// nil means the Bin.
    public var destination: URL?
}

/// Works out where each removed file goes. Pure: it doesn't touch the disk.
public enum RemovalPlanner {
    public static func plan(_ tracks: [Track], mode: RemovalMode) -> [PlannedMove] {
        switch mode {
        case .moveToBin:
            return tracks.map { PlannedMove(trackID: $0.id, source: $0.url, destination: nil) }
        case .moveToFolder(let folder):
            let rootNames = uniqueRootNames(for: tracks)
            return tracks.map { track in
                PlannedMove(
                    trackID: track.id,
                    source: track.url,
                    destination: mirroredDestination(for: track, in: folder, rootNames: rootNames)
                )
            }
        }
    }

    /// `Root/A/B/x.mp3` → `Dest/Root/A/B/x.mp3`. Without a scan root, the
    /// file's parent folder name is used as the root.
    static func mirroredDestination(for track: Track, in folder: URL, rootNames: [String: String]) -> URL {
        let file = track.url.standardizedFileURL
        guard let root = track.scanRoot?.standardizedFileURL else {
            let parent = file.deletingLastPathComponent().lastPathComponent
            return folder.appendingPathComponent(parent, isDirectory: true)
                .appendingPathComponent(file.lastPathComponent)
        }
        let rootName = rootNames[root.path] ?? root.lastPathComponent
        var destination = folder.appendingPathComponent(rootName, isDirectory: true)
        for component in relativeComponents(of: file, under: root) {
            destination.appendPathComponent(component)
        }
        return destination
    }

    /// Path components of `file` below `root`, or just the file name if it isn't inside `root`.
    static func relativeComponents(of file: URL, under root: URL) -> [String] {
        let fileParts = file.pathComponents
        let rootParts = root.pathComponents
        guard fileParts.count > rootParts.count, Array(fileParts.prefix(rootParts.count)) == rootParts else {
            return [file.lastPathComponent]
        }
        return Array(fileParts.dropFirst(rootParts.count))
    }

    /// Two scan roots with the same folder name ("Music" on two drives) get
    /// "Music" and "Music 2", so their files can't collide.
    static func uniqueRootNames(for tracks: [Track]) -> [String: String] {
        let roots = Set(tracks.compactMap { $0.scanRoot?.standardizedFileURL.path }).sorted()
        var used: Set<String> = []
        var names: [String: String] = [:]
        for path in roots {
            let base = URL(fileURLWithPath: path).lastPathComponent
            var name = base
            var n = 2
            while used.contains(name) {
                name = "\(base) \(n)"
                n += 1
            }
            used.insert(name)
            names[path] = name
        }
        return names
    }

    /// `x.mp3` → `x 2.mp3`, `x 3.mp3`, … until `exists` returns false.
    public static func uniqueDestination(for url: URL, exists: (URL) -> Bool) -> URL {
        guard exists(url) else { return url }
        let folder = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !exists(candidate) { return candidate }
            n += 1
        }
    }
}
