import Foundation
import Observation

/// Checks GitHub for a newer release of the app. It only reads the latest
/// release's version and web page; nothing is downloaded or installed, and
/// nothing is sent but the request.
@MainActor
@Observable
final class UpdateChecker {
    /// The latest release, as GitHub describes it.
    struct Release: Decodable, Equatable {
        var tagName: String
        var pageURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case pageURL = "html_url"
        }

        /// "1.2.0" for the tag "v1.2.0".
        var version: String {
            tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }
    }

    /// What a check found.
    enum Finding: Equatable {
        case newer(Release)
        case upToDate
        case failed(String)
    }

    enum Failure: Error {
        /// GitHub answered with something other than a release, such as 404
        /// when nothing has been published yet or the repository is private.
        case status(Int)
    }

    nonisolated static let latestReleaseURL = URL(string: "https://api.github.com/repos/felixhj/deduplicator/releases/latest")!
    static let checksAtLaunchKey = "checksForUpdates"
    static let skippedVersionKey = "skippedVersion"

    /// Set to show what a check found; the alert clears it.
    var finding: Finding?
    let currentVersion: String

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fetch: @Sendable () async throws -> Data

    /// `fetch` gets the latest release's JSON; tests pass their own.
    init(
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
        defaults: UserDefaults = .standard,
        fetch: @escaping @Sendable () async throws -> Data = UpdateChecker.fetchLatestRelease
    ) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.fetch = fetch
    }

    /// On unless switched off in Settings.
    var checksAtLaunch: Bool {
        defaults.object(forKey: Self.checksAtLaunchKey) as? Bool ?? true
    }

    /// At launch, only a newer version the user hasn't skipped is worth
    /// saying anything about. Failures, such as being offline, stay quiet.
    func checkAtLaunch() async {
        guard checksAtLaunch, case .newer(let release) = await check(),
              release.version != defaults.string(forKey: Self.skippedVersionKey)
        else { return }
        finding = .newer(release)
    }

    /// From the menu, whatever it finds is shown.
    func checkNow() async {
        finding = await check()
    }

    /// Stops the launch check mentioning this release again.
    func skip(_ release: Release) {
        defaults.set(release.version, forKey: Self.skippedVersionKey)
    }

    private func check() async -> Finding {
        do {
            let release = try JSONDecoder().decode(Release.self, from: try await fetch())
            return AppVersion(release.version) > AppVersion(currentVersion) ? .newer(release) : .upToDate
        } catch Failure.status(404) {
            return .failed("No release has been published on GitHub yet.")
        } catch {
            return .failed("GitHub couldn't be reached. \(error.localizedDescription)")
        }
    }

    nonisolated static func fetchLatestRelease() async throws -> Data {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.status(status) }
        return data
    }
}

/// A version such as "1.2.10", compared number by number, so 1.10 is newer
/// than 1.9. Missing numbers count as 0, so 1.2 and 1.2.0 are the same.
struct AppVersion: Comparable {
    let numbers: [Int]

    init(_ text: String) {
        numbers = text.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.numbers.count, rhs.numbers.count)
        let left = lhs.numbers + Array(repeating: 0, count: count - lhs.numbers.count)
        let right = rhs.numbers + Array(repeating: 0, count: count - rhs.numbers.count)
        return left.lexicographicallyPrecedes(right)
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
