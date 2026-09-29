import Foundation
import Testing
@testable import Deduplicator

@MainActor
struct UpdateCheckerTests {
    let storage = TestDefaults()

    /// A checker whose GitHub says the latest release is `tag`.
    func checker(running current: String, latest tag: String) -> UpdateChecker {
        let json = Data(#"{"tag_name": "\#(tag)", "html_url": "https://github.com/felixhj/deduplicator/releases/tag/\#(tag)", "name": "Deduplicator"}"#.utf8)
        return UpdateChecker(currentVersion: current, defaults: storage.defaults) { json }
    }

    func release(_ tag: String) -> UpdateChecker.Release {
        UpdateChecker.Release(tagName: tag, pageURL: URL(string: "https://github.com/felixhj/deduplicator/releases/tag/\(tag)")!)
    }

    @Test func versionsCompareNumberByNumber() {
        #expect(AppVersion("1.10") > AppVersion("1.9"))
        #expect(AppVersion("2.0.0") > AppVersion("1.99.99"))
        #expect(AppVersion("1.2") == AppVersion("1.2.0"))
        #expect(!(AppVersion("1.0.0") > AppVersion("1.0.0")))
        #expect(release("v1.2.0").version == "1.2.0")
        #expect(release("1.2.0").version == "1.2.0")
    }

    @Test func aNewerReleaseIsOfferedAtLaunch() async {
        let updates = checker(running: "1.0.0", latest: "v1.1.0")
        await updates.checkAtLaunch()
        #expect(updates.finding == .newer(release("v1.1.0")))
    }

    @Test func theSameOrAnOlderReleaseSaysNothingAtLaunch() async {
        for tag in ["v1.0.0", "v0.9.0"] {
            let updates = checker(running: "1.0.0", latest: tag)
            await updates.checkAtLaunch()
            #expect(updates.finding == nil)
        }
    }

    @Test func aSkippedReleaseIsntOfferedAgainButALaterOneIs() async {
        let updates = checker(running: "1.0.0", latest: "v1.1.0")
        updates.skip(release("v1.1.0"))
        await updates.checkAtLaunch()
        #expect(updates.finding == nil)
        let later = checker(running: "1.0.0", latest: "v1.2.0")
        await later.checkAtLaunch()
        #expect(later.finding == .newer(release("v1.2.0")))
    }

    @Test func theLaunchCheckCanBeSwitchedOff() async {
        storage.defaults.set(false, forKey: UpdateChecker.checksAtLaunchKey)
        let updates = checker(running: "1.0.0", latest: "v2.0.0")
        await updates.checkAtLaunch()
        #expect(updates.finding == nil)
        await updates.checkNow()
        #expect(updates.finding == .newer(release("v2.0.0")), "Checking from the menu still works")
    }

    @Test func checkingFromTheMenuAlwaysSaysWhatItFound() async {
        let current = checker(running: "1.0.0", latest: "v1.0.0")
        await current.checkNow()
        #expect(current.finding == .upToDate)

        let unpublished = UpdateChecker(currentVersion: "1.0.0", defaults: storage.defaults) { throw UpdateChecker.Failure.status(404) }
        await unpublished.checkNow()
        #expect(unpublished.finding == .failed("No release has been published on GitHub yet."))
        await unpublished.checkAtLaunch()
        #expect(unpublished.finding == .failed("No release has been published on GitHub yet."), "At launch, a failure changes nothing")
    }
}
