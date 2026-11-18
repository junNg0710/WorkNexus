import CoreDomain
import Foundation
import XCTest
@testable import FeatureChat

private struct FakeMcpRepository: McpSetupRepository {
    var prepared: Outcome<McpSetup>
    var refreshed: Outcome<Void> = .success(())
    func prepare() async -> Outcome<McpSetup> { prepared }
    func refreshInstalledScript() async -> Outcome<Void> { refreshed }
}

/// Ported from: test/domain/chat/mcp_setup_test.dart (macOS cases; the Windows / Linux ones have no counterpart here)
final class McpSetupTests: XCTestCase {
    private func setup(node: String? = nil, version: String? = nil) -> McpSetup {
        McpSetup(scriptPath: "/s", nodePath: node, nodeVersion: version, databasePath: "/db")
    }

    func testNeedsNode2213OrNewer() {
        for v in ["v22.13.0", "v22.20.1", "v25.2.1", "23.0.0"] { XCTAssertTrue(setup(version: v).nodeSupported, v) }
        for v in ["v22.12.9", "v20.19.0", "v9.99.0"] { XCTAssertFalse(setup(version: v).nodeSupported, v) }
    }

    func testIsNotSupportedWithoutAReadableVersion() {
        XCTAssertFalse(setup(version: nil).nodeSupported)
        XCTAssertFalse(setup(version: "garbage").nodeSupported)
        XCTAssertFalse(setup(version: "v22").nodeSupported)
    }

    func testSpotsOneVersionOfAVersionManager() {
        for p in ["/Users/me/.nvm/versions/node/v22.14.0/bin/node", "/Users/me/.local/share/fnm/node-versions/v22/installation/bin/node",
                  "/Users/me/.local/state/fnm_multishells/1_2/bin/node", "/Users/me/.asdf/installs/nodejs/22.14.0/bin/node",
                  "/Users/me/.local/share/mise/installs/node/22/bin/node", "/Users/me/.nodenv/versions/22.14.0/bin/node",
                  #"C:\Users\me\AppData\Roaming\nvm\v22.14.0\node.exe"#] {
            XCTAssertTrue(setup(node: p).nodeFromVersionManager, p)
        }
    }

    func testLeavesSystemAndHomebrewInstallsAlone() {
        for p in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/Users/me/.volta/bin/node"] {
            XCTAssertFalse(setup(node: p).nodeFromVersionManager, p)
        }
        XCTAssertFalse(setup().nodeFromVersionManager)
    }

    // MARK: BuildMcpClientConfigs

    private let full = McpSetup(scriptPath: "/Users/me/Library/Application Support/x/mcp/worknexus-mcp.mjs", nodePath: "/opt/homebrew/bin/node",
                                nodeVersion: "v25.2.1", databasePath: "/Users/me/Library/Application Support/com.worknexus.macos/worknexus.sqlite")

    func testQuotesTheAbsolutePathsAndTheDatabaseInTheClaudeCodeCommand() {
        let code = BuildMcpClientConfigs()(full).first
        XCTAssertEqual(code?.client, .claudeCode)
        XCTAssertEqual(code?.snippet, "claude mcp add worknexus -s user "
                       + "-e WORKNEXUS_DB='/Users/me/Library/Application Support/com.worknexus.macos/worknexus.sqlite' -- "
                       + "'/opt/homebrew/bin/node' '/Users/me/Library/Application Support/x/mcp/worknexus-mcp.mjs'")
    }

    func testGivesClaudeDesktopAValidMcpServersEntryWithTheDatabase() throws {
        let configs = BuildMcpClientConfigs()(full)
        XCTAssertEqual(configs.map(\.client), [.claudeCode, .claudeDesktop, .other])
        XCTAssertEqual(configs[1].configFile, "~/Library/Application Support/Claude/claude_desktop_config.json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(configs[1].snippet.utf8)) as? [String: Any])
        let entry = try XCTUnwrap((json["mcpServers"] as? [String: Any])?["worknexus"] as? [String: Any])
        XCTAssertEqual(entry["command"] as? String, "/opt/homebrew/bin/node")
        XCTAssertEqual(entry["args"] as? [String], [full.scriptPath])
        XCTAssertEqual(entry["env"] as? [String: String], ["WORKNEXUS_DB": full.databasePath])
        XCTAssertEqual(configs[2].snippet, configs[1].snippet)
    }

    func testEscapesQuotesInPathsAndFallsBackToNode() throws {
        let odd = McpSetup(scriptPath: #"/tmp/it's "here"/w.mjs"#, databasePath: "/db")
        let configs = BuildMcpClientConfigs()(odd)
        XCTAssertTrue(configs[0].snippet.contains(#"-- 'node' '/tmp/it'\''s "here"/w.mjs'"#), configs[0].snippet)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(configs[1].snippet.utf8)) as? [String: Any])
        let entry = (json["mcpServers"] as? [String: Any])?["worknexus"] as? [String: Any]
        XCTAssertEqual(entry?["command"] as? String, "node")
        XCTAssertEqual(entry?["args"] as? [String], [odd.scriptPath])
    }

    // MARK: PrepareMcpSetup / RefreshMcpScript / McpSetupModel

    func testPassesOnWhatTheRepositoryPreparesOrItsFailure() async {
        let ok = await PrepareMcpSetup(FakeMcpRepository(prepared: .success(setup())))()
        XCTAssertEqual(ok.value?.scriptPath, "/s")
        let failed = await PrepareMcpSetup(FakeMcpRepository(prepared: .failure(.storage("disk full"))))()
        XCTAssertEqual(failed.failure, .storage("disk full"))
        let refreshed = await RefreshMcpScript(FakeMcpRepository(prepared: .success(setup()), refreshed: .failure(.storage("read-only"))))()
        XCTAssertEqual(refreshed.failure, .storage("read-only"))
    }

    @MainActor
    func testModelBuildsTheConfigsAndOffersNodeWhenMissing() async {
        let model = McpSetupModel(repository: FakeMcpRepository(prepared: .success(setup(node: "/usr/bin/node", version: "v18.0.0"))))
        await model.load()
        guard case .ready(let s, let configs) = model.state else { return XCTFail("not ready") }
        XCTAssertEqual(s.nodePath, "/usr/bin/node")
        XCTAssertEqual(configs.count, 3)
        XCTAssertTrue(model.nodeMissing)

        let failing = McpSetupModel(repository: FakeMcpRepository(prepared: .failure(.notFound("This build has no MCP server"))))
        await failing.load()
        XCTAssertEqual(failing.state, .failed("This build has no MCP server"))
        XCTAssertFalse(failing.nodeMissing)
    }
}
