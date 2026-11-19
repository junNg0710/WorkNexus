import CoreDomain
import XCTest
@testable import FeatureAppUpdate

// MARK: doubles

private final class MemorySeen: SeenVersionStore, @unchecked Sendable {
    var value: String?
    var failsReading = false
    private(set) var writes: [String] = []
    init(_ value: String?) { self.value = value }
    func lastSeen() async -> Outcome<String?> { failsReading ? .failure(.storage("unreadable")) : .success(value) }
    func setLastSeen(_ version: String) async -> Outcome<Void> { value = version; writes.append(version); return .success(()) }
}

/// A canned `/releases` list for the repository (no network).
private final class ListedReleases: GitHubReleaseSource, @unchecked Sendable {
    let list: [GitHubRelease]
    init(_ list: [GitHubRelease]) { self.list = list }
    func fetchLatestStableRelease() async throws -> GitHubRelease { throw ReleaseHTTPError(status: 404) }
    func fetchStableReleases() async throws -> [GitHubRelease] { list }
    func readText(_ url: String) async throws -> String { "" }
    func downloadFile(_ url: String, to path: String, onProgress: @escaping @Sendable (Double) -> Void) async throws {}
    func sha256Of(_ path: String) throws -> String { "" }
}

private let macReleases: [ReleaseNote] = [
    ReleaseNote(version: "v1.0.0+mac", notes: "- One"),
    ReleaseNote(version: "v1.1.0+mac", notes: "- Two"),
    ReleaseNote(version: "v1.2.0+mac", notes: "  "),
    ReleaseNote(version: "v1.3.0+mac", notes: "- Four\n"),
    ReleaseNote(version: "v1.4.0-beta.1+mac", notes: "- Beta"),
]

// MARK: app_version (+mac)

final class AppVersionTests: XCTestCase {
    func testMacSuffixIsBuildMetadataOutsideTheOrder() {
        let mac = AppVersion("v1.9.5+mac"), plain = AppVersion("1.9.5")
        XCTAssertEqual(mac?.build, "mac")
        XCTAssertEqual(mac, plain)
        XCTAssertFalse(mac! < plain! || plain! < mac!)
        XCTAssertEqual(mac?.tag, "v1.9.5")
    }

    func testOrdersByNumbersNotText() {
        XCTAssertLessThan(AppVersion("v1.9.5+mac")!, AppVersion("v1.10.0+mac")!)
        XCTAssertLessThan(AppVersion("1.2.0-rc.1")!, AppVersion("v1.2.0+mac")!)
        XCTAssertNil(AppVersion("1.9"))
        XCTAssertNil(AppVersion("v1.9.5+"))
    }
}

// MARK: collect_release_notes / check_for_update (notes of every release since)

final class CollectReleaseNotesTests: XCTestCase {
    func testNewestFirstWithAHeadingPerVersionInRange() {
        let text = CollectReleaseNotes.combine(macReleases, after: "1.0.0", upTo: "v1.3.0+mac")
        XCTAssertEqual(text, "## v1.3.0\n\n- Four\n\n## v1.1.0\n\n- Two")
    }

    func testIgnoresPrereleasesAndVersionsOutsideTheRange() {
        let text = CollectReleaseNotes.combine([
            ReleaseNote(version: "v2.0.0", notes: "- Too new"),
            ReleaseNote(version: "v1.5.0-rc.1", notes: "- RC"),
            ReleaseNote(version: "1.5.0", notes: "- Five"),
        ], after: "1.4.0", upTo: "v1.5.0")
        XCTAssertEqual(text, "## v1.5.0\n\n- Five")
    }

    func testUnparseableBoundsGiveNothing() {
        XCTAssertEqual(CollectReleaseNotes.combine(macReleases, after: "dev", upTo: "v1.3.0"), "")
    }

    func testUpdateListsEveryReleaseSinceTheRunningOne() async {
        let repo = StubRepository(snapshot: snap("1.0.0", "v1.3.0+mac", notes: "- Latest only"), notes: .success(macReleases))
        let notes = await CheckForUpdate(repo)().value??.releaseNotes
        XCTAssertEqual(notes, "## v1.3.0\n\n- Four\n\n## v1.1.0\n\n- Two")
    }

    func testUpdateKeepsTheLatestNotesWhenTheListCannotBeRead() async {
        let repo = StubRepository(snapshot: snap("1.0.0", "v1.3.0+mac", notes: "- Latest only"), notes: .failure(.network("offline")))
        let notes = await CheckForUpdate(repo)().value??.releaseNotes
        XCTAssertEqual(notes, "- Latest only")
    }

    func testRepositoryKeepsOnlyThisAppsReleases() async {
        let page = "https://example.test/r"
        let repo = GitHubUpdateRepository(releases: ListedReleases([
            GitHubRelease(tagName: "v1.9.0", htmlUrl: page, notes: "- Flutter", assets: [:]),
            GitHubRelease(tagName: "v1.9.0+mac", htmlUrl: page, notes: "- Native", assets: [:]),
        ]), installer: nil, config: AppUpdateConfig(releaseTagSuffix: "+mac"), currentVersion: "1.8.0")
        let notes = await repo.fetchStableReleaseNotes().value
        XCTAssertEqual(notes, [ReleaseNote(version: "v1.9.0+mac", notes: "- Native")])
    }

    func testReleaseListSkipsDraftsAndPrereleases() throws {
        let json = #"""
        [{"tag_name":"v1.2.0+mac","html_url":"h","draft":false,"prerelease":false,"body":" - A \n"},
         {"tag_name":"v1.3.0+mac","html_url":"h","draft":true,"prerelease":false,"body":"- Draft"},
         {"tag_name":"v1.3.0-rc.1+mac","html_url":"h","draft":false,"prerelease":true,"body":"- RC"}]
        """#
        let list = try GitHubReleaseDataSource.parseReleases(Data(json.utf8))
        XCTAssertEqual(list.map(\.tagName), ["v1.2.0+mac"])
        XCTAssertEqual(list.first?.notes, "- A")
    }
}

// MARK: find_whats_new_test.dart

final class FindWhatsNewTests: XCTestCase {
    private func find(_ seen: MemorySeen, current: String = "1.3.0",
                      notes: Outcome<[ReleaseNote]> = .success(macReleases)) async -> Outcome<WhatsNew?> {
        await FindWhatsNew(releases: StubRepository(current: current, notes: notes), seen: seen)()
    }

    func testAfterAnUpdateListsEveryReleaseSinceTheLastOneRun() async {
        let seen = MemorySeen("1.0.0")
        let news = await find(seen).value ?? nil
        XCTAssertEqual(news, WhatsNew(from: "1.0.0", to: "1.3.0", notes: "## v1.3.0\n\n- Four\n\n## v1.1.0\n\n- Two"))
        XCTAssertEqual(seen.writes, ["1.3.0"])
        // Shown once: the next launch of the same build says nothing.
        let again = await find(seen).value ?? nil
        XCTAssertNil(again)
        XCTAssertEqual(seen.writes, ["1.3.0"])
    }

    func testFirstInstallShowsNothingButRemembersTheVersion() async {
        let seen = MemorySeen(nil)
        let r = await find(seen)
        XCTAssertNotNil(r.value)
        XCTAssertNil(r.value ?? nil)
        XCTAssertEqual(seen.writes, ["1.3.0"])
    }

    func testSameVersionShowsNothingAndWritesNothing() async {
        let seen = MemorySeen("1.3.0")
        let again = await find(seen).value ?? nil
        XCTAssertNil(again)
        XCTAssertTrue(seen.writes.isEmpty)
    }

    func testDowngradeShowsNothing() async {
        let seen = MemorySeen("1.4.0")
        let again = await find(seen).value ?? nil
        XCTAssertNil(again)
        XCTAssertEqual(seen.writes, ["1.3.0"])
    }

    func testFailedFetchIsTriedAgainNextLaunch() async {
        let seen = MemorySeen("1.0.0")
        let failed = await find(seen, notes: .failure(.network("offline")))
        guard case .failure(.network) = failed else { return XCTFail("expected network failure, got \(failed)") }
        XCTAssertTrue(seen.writes.isEmpty)
        XCTAssertEqual(seen.value, "1.0.0")
        // Next launch, online again: the notes show.
        let retried = await find(seen).value ?? nil
        XCTAssertEqual(retried?.from, "1.0.0")
    }

    func testUnreadableStoreIsAFailure() async {
        let seen = MemorySeen("1.0.0"); seen.failsReading = true
        guard case .failure(.storage) = await find(seen) else { return XCTFail("expected storage failure") }
    }

    func testNothingWrittenForThoseReleasesShowsNothing() async {
        let seen = MemorySeen("1.1.0")
        let news = await find(seen, current: "1.2.0").value ?? nil
        XCTAssertNil(news)
        XCTAssertEqual(seen.writes, ["1.2.0"])
    }

    @MainActor
    func testModelHoldsTheNewsUntilDismissed() async {
        let seen = MemorySeen("1.0.0")
        let model = WhatsNewModel(findWhatsNew: FindWhatsNew(releases: StubRepository(current: "1.3.0", notes: .success(macReleases)), seen: seen))
        await model.checkAtLaunch()
        XCTAssertEqual(model.news?.to, "1.3.0")
        model.dismiss()
        await model.checkAtLaunch()
        XCTAssertNil(model.news)
    }

    func testUserDefaultsStoreKeepsTheVersion() async {
        let suite = "worknexus.tests.seen.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSeenVersionStore(defaults: defaults)
        let before = await store.lastSeen().value ?? nil
        XCTAssertNil(before)
        _ = await store.setLastSeen("1.9.5")
        let after = await UserDefaultsSeenVersionStore(defaults: defaults).lastSeen().value ?? nil
        XCTAssertEqual(after, "1.9.5")
    }
}
