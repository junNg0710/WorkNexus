import CoreDomain
import CryptoKit
import XCTest
@testable import FeatureAppUpdate

// MARK: doubles

private struct StubRepository: UpdateRepository {
    var snapshot: Outcome<UpdateVersionSnapshot?>
    func currentVersion() -> String { "1.0.0" }
    func fetchLatestStableRelease() async -> Outcome<UpdateVersionSnapshot?> { snapshot }
    func download(_ update: AvailableUpdate, onProgress: @escaping @Sendable (Double) -> Void) async -> Outcome<String> {
        onProgress(0.5); onProgress(1); return .success("/staged/WorkNexus.app")
    }
    func install(stagedPath: String) async -> Outcome<Void> { .success(()) }
}

private func snap(_ current: String, _ latest: String, url: String? = nil, sha: String? = nil, notes: String = "") -> Outcome<UpdateVersionSnapshot?> {
    .success(UpdateVersionSnapshot(currentVersion: current, latestVersion: latest, releaseUrl: "https://example.test/r",
                                   releaseNotes: notes, downloadUrl: url, sha256: sha))
}

private final class FakeInstaller: UpdateInstaller, @unchecked Sendable {
    let assetName = "build.zip"
    let installPath = "/apps/WorkNexus.app"
    var writable = true
    var unpackError: Error?
    var swapped: String?
    func canReplace() -> Bool { writable }
    func unpack(zipPath: String, into directory: String) throws -> String {
        if let unpackError { throw unpackError }
        return directory
    }
    func launchSwap(stagedPath: String, scriptDir: String) throws { swapped = stagedPath }
}

private final class FakeReleases: GitHubReleaseSource, @unchecked Sendable {
    let content: String
    init(_ content: String) { self.content = content }
    func fetchLatestStableRelease() async throws -> GitHubRelease { throw ReleaseHTTPError(status: 404) }
    func readText(_ url: String) async throws -> String { "" }
    func downloadFile(_ url: String, to path: String, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try content.write(toFile: path, atomically: true, encoding: .utf8); onProgress(1)
    }
    func sha256Of(_ path: String) throws -> String {
        SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: path))).map { String(format: "%02x", $0) }.joined()
    }
}

private struct BoomError: Error {}

// MARK: check_for_update_test.dart

final class CheckForUpdateTests: XCTestCase {
    func testReturnsReleaseWhenStableVersionIsNewer() async {
        let r = await CheckForUpdate(StubRepository(snapshot: snap("1.0.9", "v1.1.0", notes: "- Faster sync")))()
        XCTAssertEqual(r.value??.latestVersion, "v1.1.0")
        XCTAssertEqual(r.value??.releaseNotes, "- Faster sync")
    }

    func testNoUpdateForSameOrOlderVersion() async {
        let same = await CheckForUpdate(StubRepository(snapshot: snap("1.2.0", "v1.2.0")))()
        let older = await CheckForUpdate(StubRepository(snapshot: snap("2.0.0", "v1.9.9")))()
        XCTAssertNil(same.value!)
        XCTAssertNil(older.value!)
    }

    func testStableIsNewerThanInstalledPrerelease() async {
        let r = await CheckForUpdate(StubRepository(snapshot: snap("1.2.0-rc.1", "v1.2.0")))()
        XCTAssertEqual(r.value??.latestVersion, "v1.2.0")
    }

    func testPrereleaseTagIsNotOffered() async {
        let r = await CheckForUpdate(StubRepository(snapshot: snap("1.0.0", "v1.1.0-alpha.1")))()
        XCTAssertNotNil(r.value)
        XCTAssertNil(r.value!)
    }

    func testMalformedVersionIsParseFailure() async {
        let r = await CheckForUpdate(StubRepository(snapshot: snap("1.0", "v1.1.0")))()
        guard case .failure(.parse) = r else { return XCTFail("expected parse failure, got \(r)") }
    }

    func testIssueUrlTargetsRepoWithVersion() {
        let url = BuildIssueReportURL()(appVersion: "1.4.1", system: "macOS 15")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/thanhnguyen293/WorkNexus/issues/new")
        let body = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value
        XCTAssertTrue(body?.contains("WorkNexus 1.4.1") == true)
        XCTAssertTrue(body?.contains("System: macOS 15") == true)
    }
}

// MARK: github_update_repository_test.dart

final class GitHubUpdateRepositoryTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("update_repo_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func update(_ sha: String) -> AvailableUpdate {
        AvailableUpdate(currentVersion: "1.0.0", latestVersion: "v1.1.0", releaseUrl: "https://example.test/release",
                        downloadUrl: "https://example.test/build.zip", sha256: sha)
    }
    private func repo(_ installer: FakeInstaller, _ content: String, quit: @escaping @Sendable () -> Void = {}) -> GitHubUpdateRepository {
        let root = self.root!
        return GitHubUpdateRepository(releases: FakeReleases(content), installer: installer, config: AppUpdateConfig(),
                                      currentVersion: "1.0.0", stagingRoot: { root }, quit: quit)
    }
    private func sha(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }

    func testChecksumMatchIsUnpacked() async {
        let r = await repo(FakeInstaller(), "build").download(update(sha("build")), onProgress: { _ in })
        XCTAssertNotNil(r.value)
    }

    func testChecksumMismatchIsRefusedAndRemoved() async throws {
        let r = await repo(FakeInstaller(), "tampered").download(update(String(repeating: "0", count: 64)), onProgress: { _ in })
        guard case .failure(.parse) = r else { return XCTFail("expected parse failure") }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testUnpackErrorBecomesFailure() async {
        let installer = FakeInstaller(); installer.unpackError = BoomError()
        let r = await repo(installer, "build").download(update(sha("build")), onProgress: { _ in })
        guard case .failure(.storage) = r else { return XCTFail("expected storage failure") }
    }

    func testUpdateWithoutVerifiedBuildCannotBeDownloaded() async {
        let u = AvailableUpdate(currentVersion: "1.0.0", latestVersion: "v1.1.0", releaseUrl: "https://example.test/release")
        let r = await repo(FakeInstaller(), "x").download(u, onProgress: { _ in })
        XCTAssertNotNil(r.failure)
    }

    func testInstallSwapsAndQuits() async {
        let installer = FakeInstaller()
        let quit = LockedFlag()
        let r = await repo(installer, "x", quit: { quit.set() }).install(stagedPath: "/staged/new.app")
        XCTAssertNotNil(r.value)
        XCTAssertEqual(installer.swapped, "/staged/new.app")
        XCTAssertTrue(quit.value)
    }

    func testInstallReportsReadOnlyLocationInsteadOfQuitting() async {
        let installer = FakeInstaller(); installer.writable = false
        let quit = LockedFlag()
        let r = await repo(installer, "x", quit: { quit.set() }).install(stagedPath: "/staged/new.app")
        guard case .failure(.storage) = r else { return XCTFail("expected storage failure") }
        XCTAssertNil(installer.swapped)
        XCTAssertFalse(quit.value)
    }

    func testAssetsAreFoundWhateverTheCaseOfTheirName() {
        let assets = ["WorkNexus-Linux-x64.tar.gz": "https://example.test/a"]
        XCTAssertEqual(GitHubUpdateRepository.assetUrl(assets, "worknexus-linux-x64.TAR.gz"), "https://example.test/a")
        XCTAssertNil(GitHubUpdateRepository.assetUrl(assets, "other.zip"))
    }

    func testChecksumLineMatchedWhateverTheCase() {
        let sums = "ABC123  WorkNexus-linux-x64.tar.gz\ndef456 *worknexus-windows-x64.zip\nnot a line\n"
        XCTAssertEqual(GitHubUpdateRepository.checksumFor("workNexus-linux-x64.tar.gz", sums: sums), "abc123")
        XCTAssertEqual(GitHubUpdateRepository.checksumFor("workNexus-windows-x64.zip", sums: sums), "def456")
        XCTAssertNil(GitHubUpdateRepository.checksumFor("missing.zip", sums: sums))
    }

    func testReleaseJsonParsing() throws {
        let json = #"{"tag_name":"v1.2.0","html_url":"https://x/r","draft":false,"prerelease":false,"body":"  notes \n","assets":[{"name":"a.zip","browser_download_url":"https://x/a.zip"},{"name":1}]}"#
        let r = try GitHubReleaseDataSource.parseRelease(Data(json.utf8))
        XCTAssertEqual(r, GitHubRelease(tagName: "v1.2.0", htmlUrl: "https://x/r", notes: "notes", assets: ["a.zip": "https://x/a.zip"]))
        let pre = #"{"tag_name":"v1.2.0","html_url":"https://x/r","draft":false,"prerelease":true}"#
        XCTAssertThrowsError(try GitHubReleaseDataSource.parseRelease(Data(pre.utf8)))
    }

    /// The whole swap, as it runs after the app quits: the helper (in a session of its own) waits for the old process,
    /// puts the new bundle in place, drops the old one, and logs what it did.
    func testTheHelperSwapsTheAppOnceTheOldProcessHasQuit() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swap_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let installed = dir.appendingPathComponent("WorkNexusMac.app"), staged = dir.appendingPathComponent("build/WorkNexusMac.app")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try Data("1.5.0".utf8).write(to: installed.appendingPathComponent("version"))
        try Data("1.5.1".utf8).write(to: staged.appendingPathComponent("version"))
        let script = dir.appendingPathComponent("install_update.sh"), log = dir.appendingPathComponent("update.log")
        try MacOSUpdateInstaller.script.write(to: script, atomically: true, encoding: .utf8)
        // The "app": a process that ends a moment later.
        let app = Process(); app.executableURL = URL(fileURLWithPath: "/bin/sleep"); app.arguments = ["0.6"]
        try app.run()
        var env = ProcessInfo.processInfo.environment; env["WN_UPDATE_NO_OPEN"] = "1"
        try MacOSUpdateInstaller.spawnDetached(["/bin/sh", script.path, "\(app.processIdentifier)", installed.path, staged.path, log.path],
                                               environment: env)
        let version = installed.appendingPathComponent("version")
        for _ in 0..<50 where (try? String(contentsOf: version, encoding: .utf8)) != "1.5.1" { Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertEqual(try String(contentsOf: version, encoding: .utf8), "1.5.1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path + ".previous"), "the old build is dropped")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path), "the new build was moved, not copied")
        XCTAssertTrue(try String(contentsOf: log, encoding: .utf8).contains("== "), "the helper says what it is doing")
    }

    func testMacInstallerScriptShape() {
        XCTAssertTrue(MacOSUpdateInstaller.script.hasPrefix("#!/bin/sh\n"))
        XCTAssertTrue(MacOSUpdateInstaller.script.contains("mv \"$2\" \"$backup\""))
        XCTAssertTrue(MacOSUpdateInstaller.script.hasSuffix("|| open \"$2\"\n"))
        XCTAssertTrue(MacOSUpdateInstaller.script.contains("-gt \(MacOSUpdateInstaller.waitLimit * 10 / 3) ]"), "a helper never waits forever")
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock(); private var v = false
    func set() { lock.lock(); v = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return v }
}

// MARK: local_auto_update_preference_test.dart

final class AutoUpdatePreferenceTests: XCTestCase {
    func testOnUntilTurnedOffAndBackOn() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("auto_update_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let pref = MarkerFileAutoUpdatePreference(file: dir.appendingPathComponent("sub/auto_update.txt"))
        let initial = await pref.isEnabled().value
        XCTAssertEqual(initial, true)
        _ = await pref.setEnabled(false)
        let off = await pref.isEnabled().value
        XCTAssertEqual(off, false)
        _ = await pref.setEnabled(true)
        let on = await pref.isEnabled().value
        XCTAssertEqual(on, true)
    }
}

// MARK: update_controller_test.dart

@MainActor
final class UpdateModelTests: XCTestCase {
    private func model(_ repo: UpdateRepository, auto: Bool = true) -> UpdateModel {
        UpdateModel(checkForUpdate: CheckForUpdate(repo), downloadUpdate: DownloadUpdate(repo), installUpdate: InstallUpdate(repo),
                    autoUpdateEnabled: { auto })
    }
    private func settle(_ m: UpdateModel, until: (UpdateState) -> Bool) async {
        for _ in 0..<200 where !until(m.state) { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func testNewReleaseDownloadsAndWaitsForRestart() async {
        let m = model(StubRepository(snapshot: snap("1.0.0", "v1.1.0", url: "https://x/a.zip", sha: "abc")))
        await m.checkInBackground()
        await settle(m) { if case .ready = $0 { true } else { false } }
        XCTAssertEqual(m.state, .ready(AvailableUpdate(currentVersion: "1.0.0", latestVersion: "v1.1.0", releaseUrl: "https://example.test/r",
                                                       downloadUrl: "https://x/a.zip", sha256: "abc"), stagedPath: "/staged/WorkNexus.app"))
    }

    func testReleaseWithoutBuildIsManual() async {
        let m = model(StubRepository(snapshot: snap("1.0.0", "v1.1.0")))
        await m.checkInBackground()
        guard case .manual = m.state else { return XCTFail("expected manual, got \(m.state)") }
    }

    func testBackgroundCheckDoesNothingWhenAutoUpdateIsOff() async {
        let m = model(StubRepository(snapshot: snap("1.0.0", "v1.1.0")), auto: false)
        await m.checkInBackground()
        XCTAssertEqual(m.state, .idle)
        _ = await m.check()    // the user asked: it looks
        guard case .manual = m.state else { return XCTFail("expected manual, got \(m.state)") }
    }

    func testNoNewerReleaseStaysIdle() async {
        let m = model(StubRepository(snapshot: snap("1.1.0", "v1.1.0")))
        let r = await m.check()
        XCTAssertNil(r.value!)
        XCTAssertEqual(m.state, .idle)
    }

    func testInstallFailureLeavesFailedState() async {
        struct Failing: UpdateRepository {
            func currentVersion() -> String { "1.0.0" }
            func fetchLatestStableRelease() async -> Outcome<UpdateVersionSnapshot?> { snap("1.0.0", "v1.1.0", url: "u", sha: "s") }
            func download(_ u: AvailableUpdate, onProgress: @escaping @Sendable (Double) -> Void) async -> Outcome<String> { .success("/p") }
            func install(stagedPath: String) async -> Outcome<Void> { .failure(.storage("no write access")) }
        }
        let m = model(Failing())
        await m.check()
        await settle(m) { if case .ready = $0 { true } else { false } }
        await m.installAndRestart()
        guard case .failed(_, let msg) = m.state else { return XCTFail("expected failed, got \(m.state)") }
        XCTAssertEqual(msg, "no write access")
    }
}
