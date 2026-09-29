import Foundation

/// Loads one of the app's JSON logs. A log that can't be read is put aside
/// beside it, never written over, and the problem is returned to report.
func loadLog<Log>(from url: URL?, empty: Log, reading load: (URL) throws -> Log) -> (log: Log, problem: String?) {
    guard let url else { return (empty, nil) }
    do {
        return (try load(url), nil)
    } catch {
        let name = url.deletingPathExtension().lastPathComponent
        let aside = url.deletingLastPathComponent().appending(path: "\(name) (unreadable \(Int(Date().timeIntervalSince1970))).json")
        try? FileManager.default.moveItem(at: url, to: aside)
        return (empty, "The log “\(url.lastPathComponent)” couldn't be read, so it was put aside as “\(aside.lastPathComponent)”.")
    }
}
