import CoreDomain
import XCTest
@testable import ToolGitHub

/// Port of test/data/github_normalize_test.dart.
final class GitHubNormalizeTests: XCTestCase {
    private let acct = "gh-acme"

    private func labels(_ names: [String]) -> [GitHubLabel] { names.map { GitHubLabel(name: $0) } }

    private func issue(state: String = "open", labels l: [String] = [],
                       repositoryUrl: String? = "https://api.github.com/repos/octo/web") -> GitHubIssue {
        GitHubIssue(number: 42, title: "An issue", body: "body", state: state, labels: labels(l),
                    htmlUrl: "https://github.com/octo/web/issues/42", repositoryUrl: repositoryUrl, updatedAt: "2026-07-01T10:00:00Z")
    }

    private func prItem(state: String = "open", draft: Bool = false, mergedAt: String? = nil) -> GitHubIssue {
        GitHubIssue(number: 7, title: "A PR", body: "body", state: state, draft: draft,
                    htmlUrl: "https://github.com/octo/web/pull/7", repositoryUrl: "https://api.github.com/repos/octo/web",
                    pullRequest: GitHubPullMarker(mergedAt: mergedAt))
    }

    private func pull(state: String = "open", draft: Bool = false, merged: Bool? = nil, mergedAt: String? = nil) -> GitHubPull {
        GitHubPull(number: 7, title: "A PR", body: "body", state: state, draft: draft, merged: merged, mergedAt: mergedAt,
                   mergeableState: "clean", requestedReviewers: [GitHubUser(login: "rev", name: "Rev Iewer")],
                   head: GitHubRef(ref: "feature/x"), base: GitHubRef(ref: "main", repo: GitHubRepo(fullName: "octo/web")),
                   htmlUrl: "https://github.com/octo/web/pull/7")
    }

    // MARK: issues

    func testOpenIssueIsTodoWithRepoKeyedIdsAndRepoPath() {
        let t = normalizeGitHubIssue(issue(), accountId: acct)
        XCTAssertEqual(t.id, "gh-acme:octo/web:issue:42")
        XCTAssertEqual(t.externalKey, "42")
        XCTAssertEqual(t.externalType, "Issue")
        XCTAssertEqual(t.providerType, .github)
        XCTAssertEqual(t.projectId, "gh-acme:octo/web")
        XCTAssertEqual(t.status, .todo)
        XCTAssertEqual(t.providerStatus, "open")
        XCTAssertEqual(t.url, "https://github.com/octo/web/issues/42")
    }

    func testClosedIssueIsDone() {
        let t = normalizeGitHubIssue(issue(state: "closed"), accountId: acct)
        XCTAssertEqual(t.status, .done)
        XCTAssertEqual(t.providerStatus, "closed")
    }

    func testInProgressAndBlockedLabels() {
        XCTAssertEqual(normalizeGitHubIssue(issue(labels: ["Doing"]), accountId: acct).status, .inprogress)
        XCTAssertEqual(normalizeGitHubIssue(issue(labels: ["blocked"]), accountId: acct).status, .blocked)
    }

    func testPriorityLabels() {
        XCTAssertEqual(normalizeGitHubIssue(issue(labels: ["priority: high"]), accountId: acct).priority, .high)
        XCTAssertEqual(normalizeGitHubIssue(issue(labels: ["P1"]), accountId: acct).priority, .urgent)
        XCTAssertEqual(normalizeGitHubIssue(issue(), accountId: acct).priority, .medium)
        XCTAssertNil(gitHubPriorityFromLabels(["bug", "enhancement"]))
        XCTAssertEqual(gitHubPriorityFromLabels(["Priority/low"]), .low)
    }

    func testParsesRepoFromHtmlUrlWhenRepositoryUrlAbsent() {
        XCTAssertEqual(normalizeGitHubIssue(issue(repositoryUrl: nil), accountId: acct).projectId, "gh-acme:octo/web")
    }

    // MARK: search feed

    func testDraftPrFromSearchFeed() {
        let t = normalizeGitHubPullFromIssue(prItem(draft: true), accountId: acct)
        XCTAssertEqual(t.status, .inprogress)
        XCTAssertEqual(t.providerStatus, "draft")
        XCTAssertEqual(t.externalType, "PullRequest")
        XCTAssertEqual(t.id, "gh-acme:octo/web:pr:7")
    }

    func testReadyOpenPrFromSearchFeedIsReview() {
        let t = normalizeGitHubPullFromIssue(prItem(), accountId: acct)
        XCTAssertEqual(t.status, .review)
        XCTAssertEqual(t.providerStatus, "open")
    }

    func testMergedPrFromSearchFeedUsesMergedAt() {
        let t = normalizeGitHubPullFromIssue(prItem(state: "closed", mergedAt: "2026-07-02T00:00:00Z"), accountId: acct)
        XCTAssertEqual(t.status, .done)
        XCTAssertEqual(t.providerStatus, "merged")
    }

    // MARK: rich PR

    func testRichDraftPrIsInProgress() {
        let t = normalizeGitHubPull(pull(draft: true), accountId: acct)
        XCTAssertEqual(t.status, .inprogress)
        XCTAssertEqual(t.providerStatus, "draft")
    }

    func testRichMergedPrIsDone() {
        let t = normalizeGitHubPull(pull(state: "closed", merged: true, mergedAt: "2026-07-02T00:00:00Z"), accountId: acct)
        XCTAssertEqual(t.status, .done)
        XCTAssertEqual(t.providerStatus, "merged")
    }

    func testRichClosedUnmergedPrIsDoneWithRawClosed() {
        let t = normalizeGitHubPull(pull(state: "closed"), accountId: acct)
        XCTAssertEqual(t.status, .done)
        XCTAssertEqual(t.providerStatus, "closed")
    }

    func testCarriesPrMetadataInProviderEntity() throws {
        let t = normalizeGitHubPull(pull(), accountId: acct)
        guard case .githubItem(let g)? = t.providerEntity else { return XCTFail("missing entity") }
        XCTAssertEqual(g.repo, "octo/web")
        XCTAssertEqual(g.headBranch, "feature/x")
        XCTAssertEqual(g.baseBranch, "main")
        XCTAssertEqual(g.mergeableState, "clean")
        XCTAssertEqual(g.draft, false)
        XCTAssertEqual(g.reviewers, ["Rev Iewer"])
        // The login too: the account knows its user by login, not by name.
        XCTAssertEqual(g.reviewerLogins, ["rev"])
    }

    func testItemStoredBeforeReviewerLoginsWereKeptStillReads() throws {
        let json = #"{"githubItem":{"_0":{"repo":"octo/web","reviewers":["Rev Iewer"]}}}"#
        let e = try JSONDecoder().decode(TicketProviderEntity.self, from: Data(json.utf8))
        guard case .githubItem(let g) = e else { return XCTFail("wrong case") }
        XCTAssertTrue(g.reviewerLogins.isEmpty)
        XCTAssertEqual(g.reviewers, ["Rev Iewer"])
    }

    func testSearchFeedAndRichNormalizersAgreeOnTicketId() {
        // The search feed sees the issue-id and the /pulls board the pull-id; keying on repo:pr:number converges them.
        let a = normalizeGitHubPullFromIssue(prItem(), accountId: acct)
        let b = normalizeGitHubPull(pull(), accountId: acct)
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a.id, "gh-acme:octo/web:pr:7")
    }

    func testPrStatusMappingBlockedLabelWinsOverOpenButNotMerged() {
        XCTAssertEqual(mapGitHubPrStatus("open", draft: false, merged: false, labels: ["blocked"]), .blocked)
        XCTAssertEqual(mapGitHubPrStatus("closed", draft: false, merged: true, labels: ["blocked"]), .done)
    }

    // MARK: repoFromUrl

    func testRepoFromUrl() {
        XCTAssertEqual(repoFromUrl("https://api.github.com/repos/octo/web"), "octo/web")
        XCTAssertEqual(repoFromUrl("https://github.com/octo/web/issues/42"), "octo/web")
        XCTAssertNil(repoFromUrl(""))
        XCTAssertNil(repoFromUrl("https://github.com/onlyone"))
        XCTAssertNil(repoFromUrl(nil))
    }

    func testDecodingDefaultsMatchDart() throws {
        let p = try GitHubClient.decodeObject(Data(#"{"number":3,"requested_reviewers":null,"assignees":null,"labels":null}"#.utf8), as: GitHubPull.self)
        XCTAssertFalse(p.draft)
        XCTAssertTrue(p.labels.isEmpty && p.assignees.isEmpty && p.requestedReviewers.isEmpty)
        XCTAssertFalse(p.isMerged)
        XCTAssertTrue(try GitHubClient.decodeObject(Data(#"{"number":3,"merged_at":"2026-07-02T00:00:00Z"}"#.utf8), as: GitHubPull.self).isMerged)
    }

    func testSourceHashMatchesDartIntHash() {
        var h = 0
        for c in "t b".utf16 { h = (h * 31 + Int(c)) & 0x7fffffff }
        XCTAssertEqual(contentHash(title: "t", body: "b"), String(h, radix: 16))
    }
}
