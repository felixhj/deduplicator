import DedupCore
import Foundation

/// Waveforms saved on disk, one small file per audio file, so each audio file
/// is only decoded once. A saved waveform is used only while the file's path,
/// size and modification date match the track's.
public struct WaveformCache: Sendable {
    struct Entry: Codable {
        var version: Int
        var path: String
        var size: Int64
        var modified: Date
        var waveform: Waveform
    }

    /// Bump when `WaveformReader` starts measuring something different, so
    /// waveforms drawn by older code are drawn again.
    static let version = 1

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// The saved waveform, if the file hasn't changed since it was drawn.
    public func waveform(for track: Track) -> Waveform? {
        guard let data = try? Data(contentsOf: url(for: track)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.version == Self.version,
              entry.path == track.url.filePath, entry.size == track.fileSize, entry.modified == track.modified
        else { return nil }
        return entry.waveform
    }

    public func store(_ waveform: Waveform, for track: Track) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let entry = Entry(version: Self.version, path: track.url.filePath, size: track.fileSize, modified: track.modified, waveform: waveform)
        try JSONEncoder().encode(entry).write(to: url(for: track), options: .atomic)
    }

    /// Named by a hash of the path, size and date. The entry holds them too, so
    /// two files whose names collide only cost a redraw.
    func url(for track: Track) -> URL {
        let key = "\(track.url.filePath)\n\(track.fileSize)\n\(track.modified.timeIntervalSinceReferenceDate)"
        // 64-bit FNV-1a, because Swift's own hashes change every run.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in key.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        let name = String(hash, radix: 16)
        return folder.appending(path: String(repeating: "0", count: 16 - name.count) + name + ".json")
    }
}
