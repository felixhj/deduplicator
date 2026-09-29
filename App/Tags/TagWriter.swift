import DedupCore
import DedupScanner
import Foundation
import Observation

/// Writes tag values copied from one copy of a track to another. Only the
/// destination file is written, off the main actor. Its new values then show
/// in the results, and every write is logged with the values before and after.
@MainActor
@Observable
final class TagWriter {
    @ObservationIgnored private let results: ResultsModel
    @ObservationIgnored private let player: PlayerModel
    @ObservationIgnored private let logURL: URL?

    /// `logURL` is where writes are logged; nil logs nothing.
    init(results: ResultsModel, player: PlayerModel, logURL: URL?) {
        self.results = results
        self.player = player
        self.logURL = logURL
    }

    /// A file's tags as they are now, or nil if TagLib can't read it.
    func tags(of track: Track) -> [String: [String]]? {
        try? TagLibFile.read(track.url).properties
    }

    /// Where tags go unless the user picks another copy: the only copy not
    /// marked for removal, which is the one being kept, or else the first
    /// other copy.
    func defaultDestination(from source: Track.ID, among copies: [Track]) -> Track.ID? {
        let others = copies.map(\.id).filter { $0 != source }
        let unmarked = copies.map(\.id).filter { !results.marked.contains($0) }
        if unmarked.count == 1, let keeper = unmarked.first, keeper != source { return keeper }
        return others.first { !results.marked.contains($0) } ?? others.first
    }

    /// Writes `changes` to `destination`'s file, and returns a problem with
    /// the log, if there was one. `before` holds the destination's values
    /// for the same keys. Throws if the file can't be written.
    func write(_ changes: [String: [String]], before: [String: [String]], to destination: Track, from source: Track) async throws -> String? {
        guard !changes.isEmpty else { return nil }
        // TagLib may move the audio within the file, so the player lets go of it first.
        if player.track?.id == destination.id {
            player.unload()
        }
        let updated = try await Task.detached {
            try TagLibFile.write(changes, to: destination.url)
            return AudioFileReader().reread(destination).track
        }.value
        results.update(updated)
        return log(TagEdit(file: destination.url, source: source.url, before: before, after: changes))
    }

    /// Why a write failed, in words.
    static func describe(_ error: any Error) -> String {
        switch error {
        case TagLibError.cannotOpen: "The file can't be opened for writing. It may be locked, read-only or moved."
        case TagLibError.cannotStore(let key): "Its format can't store the tag \(key)."
        case TagLibError.saveFailed: "Saving the file failed."
        default: error.localizedDescription
        }
    }

    private func log(_ edit: TagEdit) -> String? {
        guard let logURL else { return nil }
        var (log, problem) = loadLog(from: logURL, empty: TagEditLog(), reading: TagEditLog.load(from:))
        log.append(edit)
        do {
            try log.save(to: logURL)
        } catch {
            problem = "The tag log couldn't be saved. \(error.localizedDescription)"
        }
        return problem
    }
}
