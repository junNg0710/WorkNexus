import XCTest
@testable import ToolGitHub

/// Port of test/data/github_client_test.dart plus the auth / base-URL / Link-pagination behaviour of github_client.dart.
final class GitHubClientTests: XCTestCase {
    private let net = StubNetwork.shared
    override func setUp() { net.reset() }

    func testPaginatedListRequestsUseSharedPageSize() async throws {
        net.reset { _ in .json("[]") }
        _ = try await Fixtures.client().repos()
        XCTAssertEqual(net.requests.count, 1)
        XCTAssertEqual(net.requests[0].query["per_page"], "500")
        XCTAssertEqual(net.requests[0].url.host, "api.github.com")
        XCTAssertEqual(net.requests[0].encodedPath, "/user/repos")
        XCTAssertEqual(net.requests[0].query["affiliation"], "owner,collaborator,organization_member")
    }

    func testApiHostRequestsCarryBearerAcceptAndVersionHeaders() async throws {
        net.reset { _ in .json(#"{"login":"octo"}"#) }
        let user = try await Fixtures.client().currentUser()
        XCTAssertEqual(user.login, "octo")
        let r = net.requests[0]
        XCTAssertEqual(r.header("Authorization"), "Bearer pat")
        XCTAssertEqual(r.header("Accept"), "application/vnd.github+json")
        XCTAssertEqual(r.header("X-GitHub-Api-Version"), "2022-11-28")
    }

    func testEnterpriseBaseUrlResolvesToApiV3() {
        let r = GitHubClient.resolve("ghe.example.com/")
        XCTAssertEqual(r.apiBase, "https://ghe.example.com/api/v3")
        XCTAssertEqual(r.host, "ghe.example.com")
        XCTAssertEqual(r.webBase, "https://ghe.example.com")
        XCTAssertEqual(GitHubClient.resolve("https://ghe.example.com/api/v3").apiBase, "https://ghe.example.com/api/v3")
        XCTAssertEqual(GitHubClient.resolve("").apiBase, "https://api.github.com")
        XCTAssertEqual(GitHubClient.resolve("https://www.github.com").webBase, "https://github.com")
        XCTAssertEqual(GitHubClient.resolve("http://ghe.local:8443").apiBase, "http://ghe.local:8443/api/v3")
    }

    func testEnterpriseRequestsGoToApiV3() async throws {
        net.reset { _ in .json("[]") }
        _ = try await Fixtures.client(baseUrl: "https://ghe.example.com").repoPulls("octo/web", state: "all")
        XCTAssertEqual(net.requests[0].url.host, "ghe.example.com")
        XCTAssertEqual(net.requests[0].encodedPath, "/api/v3/repos/octo/web/pulls")
        XCTAssertEqual(net.requests[0].query["state"], "all")
        XCTAssertEqual(net.requests[0].header("Authorization"), "Bearer pat")
    }

    func testLinkHeaderPaginationFollowsRelNext() async throws {
        net.reset { req in
            switch req.query["page"] {
            case "1": return .json(#"[{"full_name":"a/one"}]"#,
                                   headers: ["Link": #"<https://api.github.com/user/repos?affiliation=owner%2Ccollaborator&page=2>; rel="next", <https://api.github.com/user/repos?page=3>; rel="last""#])
            case "2": return .json(#"[{"full_name":"a/two"}]"#, headers: ["Link": #"<https://api.github.com/user/repos?page=1>; rel="prev""#])
            default: return .json("[]")
            }
        }
        let repos = try await Fixtures.client().repos()
        XCTAssertEqual(repos.map(\.fullName), ["a/one", "a/two"])
        XCTAssertEqual(net.requests.count, 2)
    }

    func testNextPageParsing() {
        XCTAssertEqual(GitHubClient.nextPage(#"<https://x/y?page=4>; rel="next""#), 4)
        XCTAssertNil(GitHubClient.nextPage(#"<https://x/y?page=4>; rel="prev""#))
        XCTAssertNil(GitHubClient.nextPage(nil))
        XCTAssertNil(GitHubClient.nextPage(""))
    }

    func testSearchWalksItemsEnvelope() async throws {
        net.reset { req in
            req.query["page"] == "1"
                ? .json(#"{"items":[{"number":1}]}"#, headers: ["Link": #"<https://api.github.com/search/issues?page=2>; rel="next""#])
                : .json(#"{"items":[{"number":2}]}"#)
        }
        let items = try await Fixtures.client().assignedPulls()
        XCTAssertEqual(items.map(\.number), [1, 2])
        XCTAssertEqual(net.requests[0].encodedPath, "/search/issues")
        XCTAssertEqual(net.requests[0].query["q"], "is:open is:pr assignee:@me")
    }

    func testMutationPayloads() async throws {
        let c = Fixtures.client()
        try await c.updateIssue("octo/web", "42", assignees: ["amy"], state: "closed")
        try await c.mergePull("octo/web", "42")
        try await c.updateBranch("octo/web", "42")
        try await c.requestReviewers("octo/web", "42", ["bob"])
        XCTAssertEqual(net.requests.map(\.method), ["PATCH", "PUT", "PUT", "POST"])
        XCTAssertEqual(net.requests[0].json?["assignees"] as? [String], ["amy"])
        XCTAssertEqual(net.requests[0].json?["state"] as? String, "closed")
        XCTAssertEqual(net.requests[1].encodedPath, "/repos/octo/web/pulls/42/merge")
        XCTAssertEqual(net.requests[1].json?["merge_method"] as? String, "merge")
        XCTAssertEqual(net.requests[2].encodedPath, "/repos/octo/web/pulls/42/update-branch")
        XCTAssertEqual(net.requests[3].encodedPath, "/repos/octo/web/pulls/42/requested_reviewers")
        XCTAssertEqual(net.requests[3].json?["reviewers"] as? [String], ["bob"])
    }

    func testFetchBytesAttachesTokenToWebHostWithoutJsonAcceptAndNeverToCdn() async throws {
        net.reset { _ in .image([1, 2]) }
        let c = Fixtures.client()
        let data = try await c.fetchBytes("/user-attachments/assets/abc")
        XCTAssertEqual(data, Data([1, 2]))
        XCTAssertEqual(net.requests[0].url.absoluteString, "https://github.com/user-attachments/assets/abc")
        XCTAssertEqual(net.requests[0].header("Authorization"), "Bearer pat")
        XCTAssertNotEqual(net.requests[0].header("Accept"), "application/vnd.github+json")
        _ = try await c.fetchBytes("https://avatars.githubusercontent.com/u/1")
        XCTAssertNil(net.requests[1].header("Authorization"))
    }

    func testFetchBytesReturnsNilForNonImage() async throws {
        net.reset { _ in .html() }
        let data = try await Fixtures.client().fetchBytes("/user-attachments/assets/abc")
        XCTAssertNil(data)
    }
}
