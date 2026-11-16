import CoreDomain
import CoreTools
import XCTest
@testable import ToolGitHub

/// Pure presentation logic: scoping, state filters, merge-state words, picker selection, repo grouping, sorting, URLs.
/// Ports test/unit/repo_board_scope_test.dart (GitHub), the state / review-requested cases of test/widget/github_shell_test.dart.
final class PresentationLogicTests: XCTestCase {
    private func t(_ id: String, _ account: String, repo: String) -> Ticket {
        var x = PresFixtures.pr(id, repo: repo); x.accountId = account; return x
    }

    func testBoardShowsItsAccountAndOpenRepositoryOnly() {
        let tickets = [t("a", "gh1", repo: "me/app"), t("b", "gh1", repo: "me/lib"), t("c", "gh2", repo: "me/app")]
        XCTAssertEqual(scopeGitHubTickets(tickets, accountId: "gh1", scopeId: nil).map(\.id), ["a", "b"])
        XCTAssertEqual(scopeGitHubTickets(tickets, accountId: "gh1", scopeId: "me/app").map(\.id), ["a"])
        XCTAssertEqual(scopeGitHubTickets(tickets, accountId: nil, scopeId: "me/app").map(\.id), ["a", "c"])
    }

    func testTicketWithoutEntityFallsBackToItsProjectId() {
        var x = PresFixtures.issue("1", repo: "acme/web"); x.providerEntity = nil
        XCTAssertEqual(githubTicketRepo(x), "acme/web")
    }

    func testKindSplitsPullRequestsFromIssues() {
        XCTAssertTrue(githubTicketIsKind(PresFixtures.pr("1"), .pullRequest))
        XCTAssertFalse(githubTicketIsKind(PresFixtures.pr("1"), .issue))
        XCTAssertTrue(githubTicketIsKind(PresFixtures.issue("2"), .issue))
    }

    func testPrStateTabsFilterOpenMergedClosed() {
        let open = PresFixtures.pr("1"), merged = PresFixtures.pr("2", status: .done, providerStatus: "merged", merged: true)
        let closed = PresFixtures.pr("3", status: .done, providerStatus: "closed")
        XCTAssertEqual([open, merged, closed].filter(GithubPrListState.open.matches).map(\.id), ["1"])
        XCTAssertEqual([open, merged, closed].filter(GithubPrListState.merged.matches).map(\.id), ["2"])
        XCTAssertEqual([open, merged, closed].filter(GithubPrListState.closed.matches).map(\.id), ["3"])
    }

    func testReviewRequestedUsesLoginsThenDisplayNames() {
        let byLogin = PresFixtures.pr("1", reviewers: ["octocat"], reviewerLogins: ["someone"])
        let byLoginOther = PresFixtures.pr("2", reviewers: ["octocat"], reviewerLogins: ["someone"])
        let byName = PresFixtures.pr("3", reviewers: ["OCTOCAT"])
        let none = PresFixtures.pr("4")
        let me = PresFixtures.account  // handle "octocat"
        XCTAssertFalse(githubReviewRequested(byLogin, account: me), "logins win over display names")
        XCTAssertFalse(githubReviewRequested(byLoginOther, account: me))
        XCTAssertTrue(githubReviewRequested(byName, account: me))
        XCTAssertFalse(githubReviewRequested(none, account: me))
        XCTAssertTrue(githubReviewRequested(PresFixtures.pr("5", reviewerLogins: ["OctoCat"]), account: me))
    }

    func testItemStateReadsDraftMergedClosedOpen() {
        XCTAssertEqual(GithubItemState.of(PresFixtures.pr("1", draft: true)), .draft)
        XCTAssertEqual(GithubItemState.of(PresFixtures.pr("2", status: .done, providerStatus: "merged", merged: true)), .merged)
        XCTAssertEqual(GithubItemState.of(PresFixtures.pr("3", status: .done, providerStatus: "closed")), .closed)
        XCTAssertEqual(GithubItemState.of(PresFixtures.pr("4")), .open)
        XCTAssertTrue(GithubItemState.draft.isActive)
        XCTAssertFalse(GithubItemState.merged.isActive)
    }

    func testMergeStateWordsAndBranchUpdate() {
        XCTAssertEqual(humanizeMergeState("has_hooks"), "Has hooks")
        XCTAssertEqual(humanizeMergeState("behind"), "Behind")
        XCTAssertEqual(humanizeMergeState(nil), "")
        XCTAssertEqual(humanizeMergeState("  "), "")
        XCTAssertTrue(githubNeedsBranchUpdate(GitHubItemEntity(mergeableState: "behind")))
        XCTAssertTrue(githubNeedsBranchUpdate(GitHubItemEntity(mergeableState: "BEHIND")))
        XCTAssertFalse(githubNeedsBranchUpdate(GitHubItemEntity(mergeableState: "clean")))
        XCTAssertFalse(githubNeedsBranchUpdate(GitHubItemEntity()))
    }

    func testUserPickerSelection() {
        let users = [ProviderUser(account: "amy", displayName: "Amy Adams"), ProviderUser(account: "bo", displayName: "Bo B")]
        XCTAssertEqual(GithubUserSelection.initial(users: users, current: ["Amy Adams", "zed"]), ["amy"])
        XCTAssertEqual(GithubUserSelection.initial(users: users, current: ["bo"]), ["bo"])
        XCTAssertEqual(GithubUserSelection.visible(users, query: " ADA ").map(\.account), ["amy"])
        XCTAssertEqual(GithubUserSelection.visible(users, query: "").count, 2)
        XCTAssertEqual(GithubUserSelection.toggled(["amy"], "bo", multiple: false), ["bo"])
        XCTAssertEqual(GithubUserSelection.toggled(["amy"], "bo", multiple: true), ["amy", "bo"])
        XCTAssertEqual(GithubUserSelection.toggled(["amy", "bo"], "amy", multiple: true), ["bo"])
    }

    func testRepoGroupsSplitPinnedRecentRest() {
        func p(_ id: String) -> ProviderProject { ProviderProject(id: id, name: id, accountId: "gh-a") }
        let g = GithubRepoGroups(repos: [p("a/one"), p("a/two"), p("b/three")], filter: "", pinnedKeys: ["gh-a:a/one"], recentIds: ["a/two", "a/one"])
        XCTAssertEqual(g.pinned.map(\.id), ["a/one"])
        XCTAssertEqual(g.recent.map(\.id), ["a/two"], "a pinned repo is not repeated under Recent")
        XCTAssertEqual(g.rest.map(\.id), ["a/two", "b/three"])
        XCTAssertEqual(GithubRepoGroups(repos: [p("a/one"), p("b/three")], filter: " THR ", pinnedKeys: [], recentIds: []).rest.map(\.id), ["b/three"])
    }

    func testOpenCountCountsOnlyOpenItemsOfTheRepo() {
        let tickets = [PresFixtures.pr("1"), PresFixtures.pr("2", status: .done, providerStatus: "closed"),
                       PresFixtures.issue("3"), PresFixtures.issue("4", repo: "other/repo")]
        XCTAssertEqual(githubOpenCount(tickets, accountId: "gh-a", repoId: "acme/web"), 2)
        XCTAssertEqual(githubOpenCount(tickets, accountId: "nope", repoId: "acme/web"), 0)
    }

    func testSortByColumn() {
        let a = PresFixtures.pr("9", title: "b", updated: Date(timeIntervalSince1970: 100))
        let b = PresFixtures.pr("10", title: "A", updated: Date(timeIntervalSince1970: 300))
        let c = PresFixtures.pr("2", title: "c", updated: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(githubSort([a, b, c], by: TicketSort(.id, descending: true)).map(\.id), ["10", "9", "2"])
        XCTAssertEqual(githubSort([a, b, c], by: TicketSort(.id)).map(\.id), ["2", "9", "10"])
        XCTAssertEqual(githubSort([a, b, c], by: TicketSort(.title)).map(\.title), ["A", "b", "c"])
        XCTAssertEqual(githubSort([a, b, c], by: TicketSort(.updated, descending: true)).map(\.id), ["10", "2", "9"])
    }

    func testWebURLFollowsSectionAndScope() {
        var loc = ToolLocation(section: "github.pulls")
        XCTAssertEqual(githubWebURL(account: PresFixtures.account, location: loc)?.absoluteString, "https://github.com/pulls")
        loc.section = "github.issues"
        XCTAssertEqual(githubWebURL(account: PresFixtures.account, location: loc)?.absoluteString, "https://github.com/issues")
        loc.scopeId = "acme/web"
        XCTAssertEqual(githubWebURL(account: PresFixtures.account, location: loc)?.absoluteString, "https://github.com/acme/web/issues")
        var ghe = PresFixtures.account; ghe.baseUrl = "https://ghe.corp/"
        loc.section = "github.pulls"
        XCTAssertEqual(githubWebURL(account: ghe, location: loc)?.absoluteString, "https://ghe.corp/acme/web/pulls")
        ghe.baseUrl = nil
        XCTAssertEqual(githubWebURL(account: ghe, location: ToolLocation(section: "github.pulls"))?.absoluteString, "https://github.com/pulls")
    }

    func testConfirmationsWordTheirAction() {
        XCTAssertTrue(GithubPrConfirm.close.destructive)
        XCTAssertFalse(GithubPrConfirm.merge.destructive)
        XCTAssertEqual(GithubPrConfirm.merge.title("7"), "Merge #7?")
        XCTAssertTrue(GithubPrConfirm.merge.message(head: "feat", base: "main").contains("feat"))
        XCTAssertEqual(GithubPrConfirm.updateBranch.command, .updateBranch)
    }
}
