import CoreDomain
import XCTest
@testable import ToolGitLab

/// Ports of test/data/gitlab_adapter_test.dart (client mocks → URLProtocol stub at the HTTP boundary).
final class GitLabAdapterTests: XCTestCase {
    private let net = StubNetwork.shared
    private let ref = "group%2Fweb"   // the URL-encoded project ref parsed from projectId `gl-a:group/web`

    override func setUp() { net.reset() }

    private func req(_ i: Int) -> CapturedRequest { net.requests[i] }

    func testCloseIssueSendsStateEventCloseOnIssueEndpoint() async {
        let res = await Fixtures.adapter().closeIssue(Fixtures.ticket(type: "Issue"))
        XCTAssertNotNil(res.value)
        XCTAssertEqual(req(0).method, "PUT")
        XCTAssertEqual(req(0).encodedPath, "/api/v4/projects/\(ref)/issues/42")
        XCTAssertEqual(req(0).json?["state_event"] as? String, "close")
    }

    func testReopenIssueSendsStateEventReopen() async {
        _ = await Fixtures.adapter().reopenIssue(Fixtures.ticket(type: "Issue"))
        XCTAssertEqual(req(0).json?["state_event"] as? String, "reopen")
    }

    func testCloseMergeRequestSendsStateEventCloseOnMrEndpoint() async {
        _ = await Fixtures.adapter().closeMergeRequest(Fixtures.ticket(type: "MergeRequest"))
        XCTAssertEqual(req(0).encodedPath, "/api/v4/projects/\(ref)/merge_requests/42")
        XCTAssertEqual(req(0).json?["state_event"] as? String, "close")
    }

    func testMergeMergeRequestCallsMergeEndpoint() async {
        let res = await Fixtures.adapter().mergeMergeRequest(Fixtures.ticket(type: "MergeRequest"), squash: true, removeSourceBranch: false)
        XCTAssertNotNil(res.value)
        XCTAssertEqual(req(0).method, "PUT")
        XCTAssertEqual(req(0).encodedPath, "/api/v4/projects/\(ref)/merge_requests/42/merge")
        XCTAssertEqual(req(0).json?["squash"] as? Bool, true)
        XCTAssertEqual(req(0).json?["should_remove_source_branch"] as? Bool, false)
    }

    func testApproveAndUnapproveHitApprovalEndpoints() async {
        let a = Fixtures.adapter()
        _ = await a.approveMergeRequest(Fixtures.ticket(type: "MergeRequest"))
        _ = await a.unapproveMergeRequest(Fixtures.ticket(type: "MergeRequest"))
        XCTAssertEqual(req(0).encodedPath, "/api/v4/projects/\(ref)/merge_requests/42/approve")
        XCTAssertEqual(req(1).encodedPath, "/api/v4/projects/\(ref)/merge_requests/42/unapprove")
        XCTAssertEqual(req(0).method, "POST")
    }

    // MARK: setMergeRequestDraft

    private func stubTitle(_ title: String) {
        net.reset { r in r.method == "GET" ? .json(#"{"id":9,"iid":42,"project_id":3,"title":"\#(title)"}"#) : .json("{}") }
    }

    func testMarkingReadyStripsDraftPrefixFromLiveTitle() async {
        stubTitle("Draft: Fix login")
        let res = await Fixtures.adapter().setMergeRequestDraft(Fixtures.ticket(type: "MergeRequest"), draft: false)
        XCTAssertNotNil(res.value)
        XCTAssertEqual(req(1).method, "PUT")
        XCTAssertEqual(req(1).json?["title"] as? String, "Fix login")
    }

    func testMarkingDraftAddsPrefixOnce() async {
        stubTitle("Fix login")
        _ = await Fixtures.adapter().setMergeRequestDraft(Fixtures.ticket(type: "MergeRequest"), draft: true)
        XCTAssertEqual(req(1).json?["title"] as? String, "Draft: Fix login")
    }

    // MARK: rebaseMergeRequest

    func testRebaseWaitsForBackgroundRebaseToFinish() async {
        let polls = Counter()
        net.reset { r in
            if r.method == "PUT" { return .json("{}", status: 202) }
            return .json(#"{"id":9,"iid":42,"project_id":3,"rebase_in_progress":\#(polls.next() == 1 ? "true" : "false")}"#)
        }
        let res = await Fixtures.adapter().rebaseMergeRequest(Fixtures.ticket(type: "MergeRequest"))
        XCTAssertNotNil(res.value)
        let gets = net.requests.filter { $0.method == "GET" }
        XCTAssertEqual(gets.count, 2)
        XCTAssertEqual(gets[0].query["include_rebase_in_progress"], "true")
    }

    func testRebaseReportsFailureFromMergeError() async {
        net.reset { r in
            r.method == "PUT" ? .json("{}", status: 202)
                : .json(#"{"id":9,"iid":42,"project_id":3,"rebase_in_progress":false,"merge_error":"Rebase failed: conflicts"}"#)
        }
        let res = await Fixtures.adapter().rebaseMergeRequest(Fixtures.ticket(type: "MergeRequest"))
        XCTAssertEqual(res.failure?.message, "Rebase failed: conflicts")
    }

    // MARK: metadata

    func testListProjectMembersMapsDedupesAndSorts() async {
        net.reset { _ in .json("""
            [{"id":2,"username":"zoe","name":"Zoe","avatar_url":"https://cdn.example.com/zoe.png"},
             {"id":1,"username":"amy","name":"Amy"},{"id":1,"username":"amy","name":"Amy"},
             {"id":3,"username":"","name":"No login"}]
            """) }
        let res = await Fixtures.adapter().listProjectMembers(Fixtures.ticket(type: "Issue"))
        let users = res.value ?? []
        XCTAssertEqual(users.map(\.account), ["amy", "zoe"])
        XCTAssertEqual(users.first?.displayName, "Amy")
        XCTAssertEqual(users.last?.avatarUrl, "https://cdn.example.com/zoe.png")
        XCTAssertEqual(req(0).encodedPath, "/api/v4/projects/\(ref)/members/all")
    }

    func testSetReviewersResolvesLoginsToMemberIds() async {
        net.reset { r in r.method == "GET" ? .json(#"[{"id":5,"username":"amy"},{"id":6,"username":"bob"}]"#) : .json("{}") }
        let res = await Fixtures.adapter().setReviewers(Fixtures.ticket(type: "MergeRequest"), logins: ["bob"])
        XCTAssertNotNil(res.value)
        XCTAssertEqual(req(1).json?["reviewer_ids"] as? [Int], [6])
    }

    func testListProjectLabelsSortsCaseInsensitively() async {
        net.reset { _ in .json(##"[{"name":"b","color":"#111"},{"name":"A","color":"#222"}]"##) }
        let res = await Fixtures.adapter().listProjectLabels(Fixtures.ticket(type: "MergeRequest"))
        XCTAssertEqual(res.value?.map(\.name), ["A", "b"])
    }

    func testListProjectMilestonesFallsBackToIidTitle() async {
        net.reset { _ in .json(#"[{"id":12,"iid":3}]"#) }
        let res = await Fixtures.adapter().listProjectMilestones(Fixtures.ticket(type: "MergeRequest"))
        XCTAssertEqual(res.value, [ProviderMilestoneOption(id: 12, title: "#3")])
    }

    func testSetLabelsReplacesMrLabels() async {
        let res = await Fixtures.adapter().setLabels(Fixtures.ticket(type: "MergeRequest"), labels: ["backend", "review"])
        XCTAssertNotNil(res.value)
        XCTAssertEqual(req(0).json?["labels"] as? String, "backend,review")
    }

    func testSetMilestoneUsesZeroToClearAnMrMilestone() async {
        let res = await Fixtures.adapter().setMilestone(Fixtures.ticket(type: "MergeRequest"), milestoneId: nil)
        XCTAssertNotNil(res.value)
        XCTAssertEqual(req(0).json?["milestone_id"] as? Int, 0)
    }

    func testUpdateTimeTrackingSetsEstimateAndAddsSpentTime() async {
        let res = await Fixtures.adapter().updateTimeTracking(Fixtures.ticket(type: "MergeRequest"), estimate: "2h", spent: "30m",
                                                              resetEstimate: false, resetSpent: false)
        XCTAssertNotNil(res.value)
        XCTAssertEqual(req(0).encodedPath, "/api/v4/projects/\(ref)/merge_requests/42/time_estimate")
        XCTAssertEqual(req(0).json?["duration"] as? String, "2h")
        XCTAssertEqual(req(1).encodedPath, "/api/v4/projects/\(ref)/merge_requests/42/add_spent_time")
        XCTAssertEqual(req(1).json?["duration"] as? String, "30m")
    }

    func testUpdateTimeTrackingResetWinsOverValues() async {
        _ = await Fixtures.adapter().updateTimeTracking(Fixtures.ticket(type: "MergeRequest"), estimate: "2h", spent: "30m",
                                                        resetEstimate: true, resetSpent: true)
        XCTAssertEqual(net.requests.map(\.encodedPath), [
            "/api/v4/projects/\(ref)/merge_requests/42/reset_time_estimate",
            "/api/v4/projects/\(ref)/merge_requests/42/reset_spent_time",
        ])
    }

    func testListProjectItemsNormalizesMrsForMergeRequestKind() async {
        net.reset { _ in .json(#"[{"id":9,"iid":7,"project_id":3,"state":"opened"}]"#) }
        let res = await Fixtures.adapter().listProjectItems(projectId: ref, mergeRequests: true)
        let tickets = res.value ?? []
        XCTAssertEqual(tickets.count, 1)
        XCTAssertEqual(tickets.first?.externalType, "MergeRequest")
        XCTAssertEqual(tickets.first?.externalKey, "7")
        XCTAssertEqual(req(0).query["state"], "all")
        XCTAssertEqual(req(0).query["order_by"], "updated_at")
    }

    func testListMergeRequestChangesMapsDiffs() async {
        net.reset { _ in .json(#"[{"old_path":"a.txt","new_path":"b.txt","diff":"@@\n+x\n+y\n-z\n+++ no","renamed_file":true}]"#) }
        let res = await Fixtures.adapter().listMergeRequestChanges(Fixtures.ticket(type: "MergeRequest"))
        let change = res.value?.first
        XCTAssertEqual(change?.path, "b.txt")
        XCTAssertEqual(change?.status, "renamed")
        XCTAssertEqual(change?.additions, 2)
        XCTAssertEqual(change?.deletions, 1)
    }

    func testListMergeRequestCommitsMapsRows() async {
        net.reset { _ in .json(#"[{"id":"abcdef123","short_id":"abcdef1","title":" Fix it ","author_name":"Amy","authored_date":"2026-07-01T10:00:00.000+07:00"}]"#) }
        let res = await Fixtures.adapter().listMergeRequestCommits(Fixtures.ticket(type: "MergeRequest"))
        let c = res.value?.first
        XCTAssertEqual(c?.sha, "abcdef123")
        XCTAssertEqual(c?.shortSha, "abcdef1")
        XCTAssertEqual(c?.title, "Fix it")
        XCTAssertEqual(c?.date, ISO8601DateFormatter().date(from: "2026-07-01T03:00:00Z"))
    }

    // MARK: ProviderAdapter

    func testAssignTicketResolvesLoginThenUpdatesAssigneeIds() async {
        net.reset { r in r.encodedPath.hasSuffix("/users") ? .json(#"[{"id":77,"username":"amy"}]"#) : .json("{}") }
        let res = await Fixtures.adapter().assignTicket(Fixtures.ticket(type: "Issue"), assignee: "amy", comment: nil, left: nil)
        XCTAssertNotNil(res.value)
        XCTAssertEqual(req(0).query["username"], "amy")
        XCTAssertEqual(req(1).json?["assignee_ids"] as? [Int], [77])
    }

    func testAssignTicketFailsWhenNoSuchUser() async {
        net.reset { _ in .json("[]") }
        let res = await Fixtures.adapter().assignTicket(Fixtures.ticket(type: "Issue"), assignee: "ghost", comment: nil, left: nil)
        XCTAssertEqual(res.failure, .notFound("No GitLab user \"ghost\""))
    }

    func testListAssignedTicketsDedupesAssignedAndReviewMrs() async {
        net.reset { r in
            if r.encodedPath.hasSuffix("/user") { return .json(#"{"id":1,"username":"me"}"#) }
            if r.encodedPath.hasSuffix("/issues") { return .json(#"[{"id":1,"iid":1,"project_id":3,"state":"opened","updated_at":"2026-07-01T10:00:00Z"}]"#) }
            return .json(#"[{"id":2,"iid":2,"project_id":3,"state":"opened","updated_at":"2026-07-02T10:00:00Z"}]"#)   // both scopes
        }
        let res = await Fixtures.adapter().listAssignedTickets(sinceCursor: nil)
        let page = res.value
        XCTAssertEqual(page?.tickets.map(\.id), ["gl-a:issue:1", "gl-a:mr:2"])
        XCTAssertNotNil(page?.nextCursor)
        let cursor = page?.nextCursor
        let later = await Fixtures.adapter().listAssignedTickets(sinceCursor: cursor)
        XCTAssertEqual(later.value?.tickets.count, 0)   // nothing newer than the cursor
    }

    func testErrorClassification() async {
        net.reset { _ in .json("{}", status: 401) }
        let auth = await Fixtures.adapter().testConnection()
        XCTAssertEqual(auth.failure, .auth("GitLab authentication failed"))
        net.reset { _ in .json("{}", status: 404) }
        let missing = await Fixtures.adapter().getTicket(Fixtures.ticket(type: "Issue"))
        XCTAssertEqual(missing.failure, .notFound("GitLab resource not found"))
        net.reset { _ in .json("{}", status: 500) }
        let net500 = await Fixtures.adapter().listProjects()
        guard case .network? = net500.failure else { return XCTFail("expected network failure") }
        net.reset { _ in .json(#"{"id":"not-an-int","iid":1,"project_id":2}"#) }
        let bad = await Fixtures.adapter().getTicket(Fixtures.ticket(type: "Issue"))
        guard case .parse? = bad.failure else { return XCTFail("expected parse failure") }
    }

    func testPostCommentMapsNote() async {
        net.reset { _ in .json(#"{"id":5,"body":"hi","author":{"name":"Amy"},"created_at":"2026-07-01T10:00:00Z"}"#) }
        let res = await Fixtures.adapter().postComment(Fixtures.ticket(type: "MergeRequest"), body: "hi")
        XCTAssertEqual(res.value?.id, "gl-a:x:5")
        XCTAssertEqual(res.value?.authorName, "Amy")
        XCTAssertEqual(req(0).encodedPath, "/api/v4/projects/\(ref)/merge_requests/42/notes")
    }

    // MARK: getTicket on a merge request

    private func stubMr(state: String, approvals: StubResponse? = nil, compare: StubResponse? = nil) {
        net.reset { r in
            if r.encodedPath.hasSuffix("/approvals") { return approvals ?? .json("{}") }
            if r.encodedPath.hasSuffix("/repository/compare") { return compare ?? .json(#"{"commits":[{},{},{}]}"#) }
            return .json(#"{"id":9,"iid":42,"project_id":3,"state":"\#(state)","source_branch":"feature","target_branch":"develop"}"#)
        }
    }

    func testGetTicketCarriesWhoApprovedIntoCachedDetail() async {
        stubMr(state: "merged", approvals: .json(#"{"approved_by":[{"user":{"id":2,"username":"thanh","name":"Thanh"}}],"approvals_left":0,"user_has_approved":true,"user_can_approve":false}"#))
        let res = await Fixtures.adapter().getTicket(Fixtures.ticket(type: "MergeRequest"))
        guard case .gitlabItem(let e)? = res.value?.providerEntity else { return XCTFail("missing entity") }
        XCTAssertEqual(e.approvedBy, ["Thanh"])
        XCTAssertEqual(e.userHasApproved, true)
        XCTAssertEqual(e.approvalsLeft, 0)
    }

    func testGetTicketStillLoadsWhenApprovalsAreUnavailable() async {
        stubMr(state: "merged", approvals: .json("{}", status: 403))
        let res = await Fixtures.adapter().getTicket(Fixtures.ticket(type: "MergeRequest"))
        XCTAssertNotNil(res.value)
    }

    func testGetTicketStillLoadsWhenCompareFails() async {
        stubMr(state: "opened", compare: .json("{}", status: 404))
        let res = await Fixtures.adapter().getTicket(Fixtures.ticket(type: "MergeRequest"))
        XCTAssertNotNil(res.value)
    }

    func testGetTicketCountsCommitsBehindForOpenMr() async {
        stubMr(state: "opened")
        let res = await Fixtures.adapter().getTicket(Fixtures.ticket(type: "MergeRequest"))
        guard case .gitlabItem(let e)? = res.value?.providerEntity else { return XCTFail("missing entity") }
        XCTAssertEqual(e.commitsBehind, 3)
    }

    func testGetTicketSkipsCompareForMergedMr() async {
        stubMr(state: "merged")
        let res = await Fixtures.adapter().getTicket(Fixtures.ticket(type: "MergeRequest"))
        XCTAssertNotNil(res.value)
        XCTAssertFalse(net.requests.contains { $0.encodedPath.hasSuffix("/repository/compare") })
    }
}
