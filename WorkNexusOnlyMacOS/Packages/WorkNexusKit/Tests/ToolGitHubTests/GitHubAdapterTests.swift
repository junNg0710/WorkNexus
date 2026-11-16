import CoreDomain
import XCTest
@testable import ToolGitHub

/// Ports of test/data/github_adapter_test.dart (client mocks → URLProtocol stub at the HTTP boundary).
final class GitHubAdapterTests: XCTestCase {
    private let net = StubNetwork.shared
    private let ref = "octo/web"   // GitHub takes the slash literally, so it is NOT URL-encoded

    override func setUp() { net.reset() }

    func testCloseItemSetsStateClosedOnIssuesEndpoint() async {
        let res = await Fixtures.adapter().closeItem(Fixtures.ticket(type: "Issue"))
        XCTAssertNotNil(res.value)
        XCTAssertEqual(net.requests[0].method, "PATCH")
        XCTAssertEqual(net.requests[0].encodedPath, "/repos/\(ref)/issues/42")
        XCTAssertEqual(net.requests[0].json?["state"] as? String, "closed")
    }

    func testReopenItemSetsStateOpen() async {
        _ = await Fixtures.adapter().reopenItem(Fixtures.ticket(type: "Issue"))
        XCTAssertEqual(net.requests[0].json?["state"] as? String, "open")
    }

    func testCloseItemClosesPrViaSameIssuesEndpoint() async {
        _ = await Fixtures.adapter().closeItem(Fixtures.ticket(type: "PullRequest"))
        XCTAssertEqual(net.requests[0].encodedPath, "/repos/\(ref)/issues/42")
        XCTAssertEqual(net.requests[0].json?["state"] as? String, "closed")
    }

    func testMergePullCallsMergeEndpoint() async {
        let res = await Fixtures.adapter().mergePull(Fixtures.ticket(type: "PullRequest"))
        XCTAssertNotNil(res.value)
        XCTAssertEqual(net.requests[0].method, "PUT")
        XCTAssertEqual(net.requests[0].encodedPath, "/repos/\(ref)/pulls/42/merge")
        XCTAssertEqual(net.requests[0].json?["merge_method"] as? String, "merge")
    }

    func testUpdateBranchCallsUpdateBranchEndpoint() async {
        _ = await Fixtures.adapter().updateBranch(Fixtures.ticket(type: "PullRequest"))
        XCTAssertEqual(net.requests[0].encodedPath, "/repos/\(ref)/pulls/42/update-branch")
    }

    func testListRepoAssigneesMapsDedupesAndSorts() async {
        net.reset { _ in .json(#"[{"login":"zoe","name":"Zoe"},{"login":"amy","name":"Amy"},{"login":"amy","name":"Amy"},{"login":"","name":"No login"}]"#) }
        let res = await Fixtures.adapter().listRepoAssignees(Fixtures.ticket(type: "Issue"))
        let users = res.value ?? []
        XCTAssertEqual(users.map(\.account), ["amy", "zoe"])
        XCTAssertEqual(users.first?.displayName, "Amy")
        XCTAssertEqual(net.requests[0].encodedPath, "/repos/\(ref)/assignees")
    }

    func testListRepoItemsNormalizesPrsForPullRequestKind() async {
        net.reset { _ in .json(#"[{"number":7,"state":"open"}]"#) }
        let res = await Fixtures.adapter().listRepoItems(repo: ref, pullRequests: true)
        let tickets = res.value ?? []
        XCTAssertEqual(tickets.count, 1)
        XCTAssertEqual(tickets.first?.externalType, "PullRequest")
        XCTAssertEqual(tickets.first?.externalKey, "7")
        XCTAssertEqual(net.requests[0].encodedPath, "/repos/\(ref)/pulls")
        XCTAssertEqual(net.requests[0].query["sort"], "updated")
        XCTAssertEqual(net.requests[0].query["direction"], "desc")
    }

    func testListRepoItemsDropsPullRequestsFromIssueSlice() async {
        net.reset { _ in .json(#"[{"number":1,"state":"open"},{"number":2,"state":"open","pull_request":{}}]"#) }
        let res = await Fixtures.adapter().listRepoItems(repo: ref, pullRequests: false)
        XCTAssertEqual(res.value?.map(\.externalKey), ["1"])
        XCTAssertEqual(res.value?.first?.externalType, "Issue")
    }

    func testSetReviewersIsAdditiveAndSkipsEmptyList() async {
        let a = Fixtures.adapter()
        let empty = await a.setReviewers(Fixtures.ticket(type: "PullRequest"), logins: [])
        XCTAssertNotNil(empty.value)
        XCTAssertTrue(net.requests.isEmpty)
        _ = await a.setReviewers(Fixtures.ticket(type: "PullRequest"), logins: ["bob"])
        XCTAssertEqual(net.requests[0].encodedPath, "/repos/\(ref)/pulls/42/requested_reviewers")
    }

    func testAssignTicketUsesLoginDirectlyAndPostsComment() async {
        net.reset { r in r.encodedPath.hasSuffix("/comments") ? .json(#"{"id":1,"body":"take it"}"#) : .json("{}") }
        let res = await Fixtures.adapter().assignTicket(Fixtures.ticket(type: "Issue"), assignee: "amy", comment: "take it", left: nil)
        XCTAssertNotNil(res.value)
        XCTAssertEqual(net.requests[0].json?["assignees"] as? [String], ["amy"])
        XCTAssertEqual(net.requests[1].encodedPath, "/repos/\(ref)/issues/42/comments")
        XCTAssertEqual(net.requests[1].json?["body"] as? String, "take it")
    }

    func testGetTicketRoutesByKind() async {
        net.reset { r in
            r.encodedPath.contains("/pulls/")
                ? .json(#"{"number":42,"state":"open","draft":true,"head":{"ref":"f"},"base":{"ref":"main"}}"#)
                : .json(#"{"number":42,"state":"open"}"#)
        }
        let pr = await Fixtures.adapter().getTicket(Fixtures.ticket(type: "PullRequest"))
        XCTAssertEqual(pr.value?.providerStatus, "draft")
        XCTAssertEqual(pr.value?.id, "gh-a:octo/web:pr:42")
        let issue = await Fixtures.adapter().getTicket(Fixtures.ticket(type: "Issue"))
        XCTAssertEqual(issue.value?.id, "gh-a:octo/web:issue:42")
    }

    func testListCommentsSkipsBlankBodiesAndActivityHumanizesEvents() async {
        net.reset { r in
            r.encodedPath.hasSuffix("/comments")
                ? .json(#"[{"id":1,"body":"  "},{"id":2,"body":"hi","user":{"login":"amy"},"created_at":"2026-07-01T10:00:00Z"}]"#)
                : .json(#"[{"id":9,"event":"review_requested","actor":{"login":"amy"},"created_at":"2026-07-01T10:00:00Z"}]"#)
        }
        let a = Fixtures.adapter()
        let comments = await a.listComments(Fixtures.ticket(type: "Issue"))
        XCTAssertEqual(comments.value?.map(\.id), ["gh-a:x:2"])
        XCTAssertEqual(comments.value?.first?.authorName, "amy")
        let activity = await a.listActivity(Fixtures.ticket(type: "Issue"))
        XCTAssertEqual(activity.value?.first?.action, "review requested")
    }

    func testListAssignedTicketsDedupesPrsAcrossSearches() async {
        net.reset { r in
            let q = r.query["q"] ?? ""
            if q.contains("is:issue") { return .json(#"{"items":[{"number":1,"state":"open","repository_url":"https://api.github.com/repos/octo/web","updated_at":"2026-07-01T10:00:00Z"}]}"#) }
            return .json(#"{"items":[{"number":7,"state":"open","repository_url":"https://api.github.com/repos/octo/web","pull_request":{},"updated_at":"2026-07-02T10:00:00Z"}]}"#)
        }
        let res = await Fixtures.adapter().listAssignedTickets(sinceCursor: nil)
        XCTAssertEqual(res.value?.tickets.map(\.id), ["gh-a:octo/web:issue:1", "gh-a:octo/web:pr:7"])
        XCTAssertNotNil(res.value?.nextCursor)
    }

    func testPullCommitsAndFilesMapRows() async {
        net.reset { r in
            r.encodedPath.hasSuffix("/commits")
                ? .json(#"[{"sha":"abcdef0123456","commit":{"message":"Fix it\n\nbody","author":{"name":"Amy","date":"2026-07-01T10:00:00Z"}}}]"#)
                : .json(#"[{"filename":"a.swift","additions":3,"deletions":1,"status":"modified","patch":"@@"}]"#)
        }
        let a = Fixtures.adapter()
        let commits = await a.listPullCommits(Fixtures.ticket(type: "PullRequest"))
        XCTAssertEqual(commits.value?.first?.shortSha, "abcdef0")
        XCTAssertEqual(commits.value?.first?.title, "Fix it")
        XCTAssertEqual(commits.value?.first?.author, "Amy")
        XCTAssertNotNil(commits.value?.first?.date)
        let files = await a.listPullFiles(Fixtures.ticket(type: "PullRequest"))
        XCTAssertEqual(files.value, [RepoFileChange(path: "a.swift", additions: 3, deletions: 1, status: "modified", diff: "@@")])
    }

    func testListProjectsMapsRepos() async {
        net.reset { _ in .json(#"[{"full_name":"octo/web"}]"#) }
        let res = await Fixtures.adapter().listProjects()
        XCTAssertEqual(res.value, [ProviderProject(id: "octo/web", name: "octo/web", accountId: "gh-a")])
    }

    func testErrorClassification() async {
        net.reset { _ in .json("{}", status: 403) }
        let auth = await Fixtures.adapter().testConnection()
        XCTAssertEqual(auth.failure, .auth("GitHub authentication failed"))
        net.reset { _ in .json("{}", status: 404) }
        let missing = await Fixtures.adapter().getTicket(Fixtures.ticket(type: "Issue"))
        XCTAssertEqual(missing.failure, .notFound("GitHub resource not found"))
        net.reset { _ in .json("{}", status: 502) }
        let gateway = await Fixtures.adapter().listProjects()
        guard case .network? = gateway.failure else { return XCTFail("expected network failure") }
        net.reset { _ in .json(#"{"number":"x"}"#) }
        let bad = await Fixtures.adapter().getTicket(Fixtures.ticket(type: "Issue"))
        guard case .parse? = bad.failure else { return XCTFail("expected parse failure") }
    }

    func testBugWorkflowIsUnsupported() async {
        let res = await Fixtures.adapter().resolveBug(Fixtures.ticket(type: "Issue"), resolution: "fixed", resolvedBuild: nil, assignee: nil, comment: nil)
        XCTAssertEqual(res.failure, .unexpected("resolveBug is ZenTao-only; GitHub uses close/reopen"))
    }
}
