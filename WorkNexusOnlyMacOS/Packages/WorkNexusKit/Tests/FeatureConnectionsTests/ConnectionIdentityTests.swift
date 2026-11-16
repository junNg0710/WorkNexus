import CoreDomain
import XCTest
@testable import FeatureConnections

/// Test vectors computed independently from lib/core/util/content_hash.dart + connection_controllers.dart.
final class ConnectionIdentityTests: XCTestCase {
    func testIntHashMatchesDart() {
        XCTAssertEqual(ConnectionIdentity.intHash(""), 0)
        XCTAssertEqual(ConnectionIdentity.intHash("https://zentao.example.com/zentao"), 1_549_718_961)
        XCTAssertEqual(ConnectionIdentity.intHash("https://gitlab.com"), 1_443_336_605)
        XCTAssertEqual(ConnectionIdentity.hex("https://github.com"), "248f9105")
        XCTAssertEqual(ConnectionIdentity.hex("Company C"), "233c3540")
    }

    func testSlug() {
        XCTAssertEqual(ConnectionIdentity.slug("Jun.Ng_01"), "jun-ng-01")
        XCTAssertEqual(ConnectionIdentity.slug("  --A b--"), "a-b")
        XCTAssertEqual(ConnectionIdentity.slug("Công ty"), "c-ng-ty")
        XCTAssertEqual(ConnectionIdentity.slug("---"), "")
    }

    func testAccountIds() {
        XCTAssertEqual(ConnectionIdentity.accountId(provider: .zentao, username: "Jun.Ng", baseUrl: "https://zentao.example.com/zentao"),
                       "zt-jun-ng-5c5ed5b1")
        XCTAssertEqual(ConnectionIdentity.accountId(provider: .gitlab, username: "jun", baseUrl: "https://gitlab.com"), "gl-jun-5607919d")
        XCTAssertEqual(ConnectionIdentity.accountId(provider: .github, username: "jun", baseUrl: "https://github.com"), "gh-jun-248f9105")
        // GitHub / GitLab hash the URL as typed: a trailing blank changes the id.
        XCTAssertEqual(ConnectionIdentity.accountId(provider: .gitlab, username: "jun", baseUrl: "https://gitlab.com/ "), "gl-jun-7269a42e")
        XCTAssertEqual(CredentialKey.accountSecret("zt-jun-ng-5c5ed5b1"), "secret:zt-jun-ng-5c5ed5b1")
    }

    func testWorkspaceIdInitialsAndColor() {
        XCTAssertEqual(ConnectionIdentity.workspaceId(name: "Company C"), "ws-company-c-233c3540")
        XCTAssertEqual(ConnectionIdentity.initials("Company C"), "CC")
        XCTAssertEqual(ConnectionIdentity.initials("Erp"), "E")
        XCTAssertEqual(ConnectionIdentity.initials("   "), "?")
        XCTAssertEqual(ConnectionIdentity.pickColor("Company C"), ConnectionIdentity.palette[2])
        XCTAssertEqual(ConnectionIdentity.pickColor("MyWorkspace"), ConnectionIdentity.palette[1])
    }

    func testInitialWorkspaceOnlyWhenExactlyOne() {
        let a = Workspace(id: "a", name: "A", shortCode: "A", colorValue: 0), b = Workspace(id: "b", name: "B", shortCode: "B", colorValue: 0)
        XCTAssertNil(ConnectionIdentity.initialWorkspaceId([]))
        XCTAssertEqual(ConnectionIdentity.initialWorkspaceId([a]), "a")
        XCTAssertNil(ConnectionIdentity.initialWorkspaceId([a, b]))
    }
}

final class TokenSettingsURLTests: XCTestCase {
    func testGitHub() {
        let tail = "/settings/tokens/new?scopes=repo,read:org&description=WorkNexus"
        XCTAssertEqual(TokenSettingsURL.github(""), "https://github.com" + tail)
        XCTAssertEqual(TokenSettingsURL.github("https://api.github.com/"), "https://github.com" + tail)
        XCTAssertEqual(TokenSettingsURL.github("ghe.corp.io/api/v3"), "https://ghe.corp.io" + tail)
    }

    func testGitLabSaaSUsesModernPathSelfHostedLegacy() {
        XCTAssertEqual(TokenSettingsURL.gitlab(""), "https://gitlab.com/-/user_settings/personal_access_tokens?name=WorkNexus&scopes=api")
        XCTAssertEqual(TokenSettingsURL.gitlab("git.corp.io/api/v4/"), "https://git.corp.io/-/profile/personal_access_tokens?name=WorkNexus&scopes=api")
    }
}

final class RenameWorkspaceTests: XCTestCase {
    private let ws = Workspace(id: "w", name: "Old", shortCode: "O", colorValue: 1)

    func testTrimsNameAndDrawsLettersFromIt() {
        let r = RenameWorkspace()(WorkspaceRename(workspace: ws, name: "  Company A ", shortCode: " "))
        XCTAssertEqual(r.value?.name, "Company A")
        XCTAssertEqual(r.value?.shortCode, "CA")
        XCTAssertEqual(RenameWorkspace.shortCode(of: "Acme"), "ACM")
        XCTAssertEqual(RenameWorkspace.shortCode(of: "a b c d"), "ABC")
    }

    func testRefusals() {
        XCTAssertEqual(RenameWorkspace()(WorkspaceRename(workspace: ws, name: " ", shortCode: "")).failure,
                       .validation("Name is required", fields: ["name": "missing"]))
        let longName = String(repeating: "x", count: 41)
        XCTAssertEqual(RenameWorkspace()(WorkspaceRename(workspace: ws, name: longName, shortCode: "")).failure?.validationFields["name"], "tooLong")
        XCTAssertEqual(RenameWorkspace()(WorkspaceRename(workspace: ws, name: "ok", shortCode: "abcde")).failure?.validationFields["shortCode"], "tooLong")
    }

    func testPersonalKeepsNameButChangesLetters() {
        var p = ws; p.isPersonal = true; p.name = "Personal"
        let r = RenameWorkspace()(WorkspaceRename(workspace: p, name: "", shortCode: "me"))
        XCTAssertEqual(r.value?.name, "Personal")
        XCTAssertEqual(r.value?.shortCode, "ME")
    }
}

private extension Failure {
    var validationFields: [String: String] { if case .validation(_, let f) = self { f } else { [:] } }
}
