import CoreDomain
import Foundation
import XCTest
@testable import FeatureChat

/// Records the programs a probe runs and answers from a table.
private final class FakeRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    let answer: @Sendable (String, [String]) -> String?
    init(_ answer: @escaping @Sendable (String, [String]) -> String?) { self.answer = answer }
    var calls: [String] { lock.withLock { _calls } }
    var run: RunProcess {
        { [self] exe, args in lock.withLock { _calls.append("\(exe) \(args.joined(separator: " "))") }; return answer(exe, args) }
    }
}

/// Ported from: test/data/chat/mcp_setup_data_test.dart (macOS cases; Windows' `where` has no counterpart here)
final class McpSetupDataTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("wn_mcp_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    // MARK: NodeRuntimeProbe

    func testAsksTheLoginShellThenChecksTheVersion() async {
        let runner = FakeRunner { exe, _ in
            exe == "/bin/zsh" ? "/Users/me/.nvm/bin/node\n" : exe == "/Users/me/.nvm/bin/node" ? "v22.14.0\n" : nil
        }
        let found = await NodeRuntimeProbe(run: runner.run, environment: ["SHELL": "/bin/zsh"]).findAll()
        XCTAssertEqual(found.first, NodeRuntimeProbe.Found(path: "/Users/me/.nvm/bin/node", version: "v22.14.0"))
        // Found by the login shell: no interactive shell needed.
        XCTAssertTrue(runner.calls.filter { $0.contains("-lic") }.isEmpty)
    }

    func testFallsBackToTheUsualInstallPlaces() async {
        let runner = FakeRunner { exe, _ in exe == "/usr/local/bin/node" ? "v23.0.0" : nil }
        let found = await NodeRuntimeProbe(run: runner.run, environment: [:]).findAll()
        XCTAssertEqual(found.map(\.path), ["/usr/local/bin/node"])
        XCTAssertTrue(runner.calls.contains { $0.contains("-lic") }, "an interactive shell is tried when the login shell has none")
    }

    func testFindsNothingWithoutNode() async {
        let v1 = await NodeRuntimeProbe(run: FakeRunner { _, _ in nil }.run, environment: [:]).findAll().isEmpty
        XCTAssertTrue(v1)
    }

    func testListsEveryNodeThatRunsOnceEachPathOrderFirst() async {
        let runner = FakeRunner { exe, _ in
            switch exe {
            case "/bin/zsh": "/usr/local/bin/node\n"
            case "/usr/local/bin/node": "v18.20.0"
            case "/opt/homebrew/bin/node": "v25.2.1"
            default: nil
            }
        }
        let found = await NodeRuntimeProbe(run: runner.run, environment: ["SHELL": "/bin/zsh"]).findAll()
        XCTAssertEqual(found, [.init(path: "/usr/local/bin/node", version: "v18.20.0"), .init(path: "/opt/homebrew/bin/node", version: "v25.2.1")])
    }

    func testResolvesFnmPerShellLinksAndShimsToTheRealNode() async {
        let fnm = "/Users/me/.local/state/fnm_multishells/42_17/bin/node"
        let real = "/Users/me/.local/share/fnm/node-versions/v22.14.0/installation/bin/node"
        let runner = FakeRunner { exe, args in
            switch (exe, args.first) {
            case ("/bin/zsh", _): "\(fnm)\n"
            case (fnm, "--version"): "v22.14.0"
            case (fnm, "-p"): "\(real)\n"
            default: nil
            }
        }
        let v2 = await NodeRuntimeProbe(run: runner.run, environment: ["SHELL": "/bin/zsh"]).findAll().map(\.path)
        XCTAssertEqual(v2, [real])
    }

    func testKeepsAHomebrewLinkAsItIs() async {
        let runner = FakeRunner { exe, _ in exe == "/opt/homebrew/bin/node" ? "v25.2.1" : nil }
        let v3 = await NodeRuntimeProbe(run: runner.run, environment: [:]).findAll().map(\.path)
        XCTAssertEqual(v3, ["/opt/homebrew/bin/node"])
        XCTAssertTrue(runner.calls.filter { $0.contains("execPath") }.isEmpty)
    }

    func testTheRealRunnerReturnsStdoutOnlyOnSuccess() async {
        let v4 = await NodeRuntimeProbe.runProcess("/bin/echo", ["v1.2.3"])?.trimmingCharacters(in: .newlines)
        XCTAssertEqual(v4, "v1.2.3")
        let v5 = await NodeRuntimeProbe.runProcess("/usr/bin/false", [])
        XCTAssertNil(v5)
        let v6 = await NodeRuntimeProbe.runProcess("/no/such/node", ["--version"])
        XCTAssertNil(v6)
    }

    // MARK: McpScriptInstaller

    private func bundled(_ text: String) throws -> URL {
        let url = dir.appendingPathComponent("bundle-\(UUID().uuidString).mjs")
        try Data(text.utf8).write(to: url)
        return url
    }

    func testCopiesTheScriptAndRewritesItOnlyWhenItChanged() throws {
        let target = dir.appendingPathComponent("mcp", isDirectory: true)
        let path = try McpScriptInstaller(source: try bundled("v1"), directory: target).install()
        XCTAssertEqual(path, target.appendingPathComponent("worknexus-mcp.mjs").path)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "v1")
        let before = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
        Thread.sleep(forTimeInterval: 0.02)
        _ = try McpScriptInstaller(source: try bundled("v1"), directory: target).install()
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date, before)
        _ = try McpScriptInstaller(source: try bundled("v2"), directory: target).install()
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "v2")
    }

    func testRefreshUpdatesAnInstalledCopyAndCreatesNone() throws {
        let target = dir.appendingPathComponent("mcp", isDirectory: true)
        XCTAssertNil(try McpScriptInstaller(source: try bundled("v1"), directory: target).refresh())
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("worknexus-mcp.mjs").path))
        _ = try McpScriptInstaller(source: try bundled("v1"), directory: target).install()
        let path = try McpScriptInstaller(source: try bundled("v2"), directory: target).refresh()
        XCTAssertEqual(try String(contentsOfFile: try XCTUnwrap(path), encoding: .utf8), "v2")
    }

    // MARK: LocalMcpSetupRepository

    private func repository(script: URL?, nodes: @escaping @Sendable (String, [String]) -> String?) -> LocalMcpSetupRepository {
        LocalMcpSetupRepository(installer: McpScriptInstaller(source: script, directory: dir.appendingPathComponent("mcp")),
                                probe: NodeRuntimeProbe(run: FakeRunner(nodes).run, environment: ["SHELL": "/bin/zsh"]), databasePath: "/db.sqlite")
    }

    func testReturnsTheInstalledScriptTheDatabaseAndTheNodeFound() async throws {
        let repo = repository(script: try bundled("x")) { exe, _ in exe == "/opt/homebrew/bin/node" ? "v25.2.1" : nil }
        let v7 = (await repo.prepare()).value
        let setup = try XCTUnwrap(v7)
        XCTAssertTrue(setup.scriptPath.hasSuffix("/mcp/worknexus-mcp.mjs"))
        XCTAssertEqual(setup.nodePath, "/opt/homebrew/bin/node")
        XCTAssertEqual(setup.databasePath, "/db.sqlite")
    }

    func testPrefersARecentEnoughNodeOverAnOlderOneFirstInPath() async throws {
        let repo = repository(script: try bundled("x")) { exe, _ in
            switch exe { case "/bin/zsh": "/usr/local/bin/node"; case "/usr/local/bin/node": "v18.0.0"; case "/opt/homebrew/bin/node": "v22.13.0"; default: nil }
        }
        let v8 = (await repo.prepare()).value?.nodeVersion
        XCTAssertEqual(v8, "v22.13.0")
    }

    func testStillNamesAnOldNodeWhenThereIsNoOther() async throws {
        let repo = repository(script: try bundled("x")) { exe, _ in exe == "/usr/bin/node" ? "v18.0.0" : nil }
        let v9 = (await repo.prepare()).value
        let setup = try XCTUnwrap(v9)
        XCTAssertEqual(setup.nodeVersion, "v18.0.0")
        XCTAssertFalse(setup.nodeSupported)
    }

    func testABuildWithoutTheScriptIsNotFoundAndRefreshingWritesNothing() async {
        let repo = repository(script: nil) { _, _ in nil }
        guard case .notFound? = (await repo.prepare()).failure else { return XCTFail("expected notFound") }
        let v10 = (await repository(script: dir.appendingPathComponent("absent.mjs")) { _, _ in nil }.refreshInstalledScript()).value
        XCTAssertNotNil(v10)
    }
}
