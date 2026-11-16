import CoreDomain
import CoreTools
import CoreUI
import XCTest
@testable import ToolGitLab

/// The pure presentation rules: scoping, state tabs and chips, the MR phase, merge-state wording, template runs, the
/// namespace tree grouping, URLs and the editors' selection rules. Ports of gitlab_mr_phase_test.dart,
/// gitlab_default_kind_test.dart and the filtering cases of gitlab_shell_test.dart.
final class PresentationLogicTests: XCTestCase {
    private let account = GLPresFixtures.account

    // MARK: gitlab_mr_phase_test.dart

    func testPhaseIsReadFromTheRawStatus() {
        let plain = GitLabItemEntity()
        func mr(_ status: String) -> Ticket { GLPresFixtures.mr("1", providerStatus: status) }
        XCTAssertEqual(GitlabMrPhase.of(mr("merged"), plain), .merged)
        XCTAssertEqual(GitlabMrPhase.of(mr("closed"), plain), .closed)
        XCTAssertEqual(GitlabMrPhase.of(mr("draft"), plain), .draft)
        XCTAssertEqual(GitlabMrPhase.of(mr("opened"), plain), .open)
        XCTAssertEqual(GitlabMrPhase.of(mr("opened"), GitLabItemEntity(draft: true)), .draft, "an opened MR flagged draft is a draft")
    }

    func testOnlyDraftAndOpenAreActive() {
        XCTAssertEqual([GitlabMrPhase.draft, .open, .merged, .closed].filter(\.isActive), [.draft, .open])
    }

    func testNeedsRebaseOnNeedRebaseOrWhenBehindTarget() {
        XCTAssertTrue(gitlabMrNeedsRebase(GitLabItemEntity(mergeStatus: "need_rebase")))
        XCTAssertTrue(gitlabMrNeedsRebase(GitLabItemEntity(mergeStatus: "mergeable", commitsBehind: 3)))
        XCTAssertFalse(gitlabMrNeedsRebase(GitLabItemEntity(mergeStatus: "mergeable")))
    }

    // MARK: scoping

    func testProjectScopeMatchesNumericIdPathOrProjectId() {
        let t = GLPresFixtures.mr("1", projectId: 12, path: "icom/web/app")
        XCTAssertTrue(gitlabTicketInProject(t, "12"))
        XCTAssertTrue(gitlabTicketInProject(t, "icom/web/app"))
        XCTAssertFalse(gitlabTicketInProject(t, "13"))
        var bare = t; bare.providerEntity = nil; bare.projectId = "99"
        XCTAssertTrue(gitlabTicketInProject(bare, "99"))
    }

    func testScopeKeepsOnlyThisAccountsGitLabItemsInTheProject() {
        var otherAccount = GLPresFixtures.mr("2"); otherAccount.accountId = "gl-b"
        var github = GLPresFixtures.mr("3"); github.providerType = .github
        let all = [GLPresFixtures.mr("1"), otherAccount, github, GLPresFixtures.mr("4", projectId: 7, path: "x/y")]
        XCTAssertEqual(scopeGitLabTickets(all, accountId: "gl-a", scopeId: nil).map(\.id), ["1", "4"])
        XCTAssertEqual(scopeGitLabTickets(all, accountId: "gl-a", scopeId: "12").map(\.id), ["1"])
        XCTAssertEqual(scopeGitLabTickets(all, accountId: nil, scopeId: "12").map(\.id), ["1", "2"])
    }

    func testKindSeparatesMergeRequestsFromIssues() {
        XCTAssertTrue(gitlabTicketIsKind(GLPresFixtures.mr("1"), .mergeRequest))
        XCTAssertFalse(gitlabTicketIsKind(GLPresFixtures.mr("1"), .issue))
        XCTAssertTrue(gitlabTicketIsKind(GLPresFixtures.issue("2"), .issue))
        XCTAssertFalse(gitlabTicketIsKind(GLPresFixtures.issue("2"), .mergeRequest))
    }

    // MARK: gitlab_shell_test.dart — state tabs and chips

    func testStateTabsFilterByRawStatus() {
        let open = GLPresFixtures.mr("1"), merged = GLPresFixtures.mr("2", status: .done, providerStatus: "merged")
        let closed = GLPresFixtures.mr("3", status: .done, providerStatus: "closed"), draft = GLPresFixtures.mr("4", providerStatus: "draft")
        let all = [open, merged, closed, draft]
        XCTAssertEqual(all.filter(GitlabMrListState.open.matches).map(\.id), ["1", "4"])
        XCTAssertEqual(all.filter(GitlabMrListState.merged.matches).map(\.id), ["2"])
        XCTAssertEqual(all.filter(GitlabMrListState.closed.matches).map(\.id), ["3"], "a merged MR is not a closed one")
    }

    func testChipsFilterDraftInReviewAndAssignedToMe() {
        var draft = GLPresFixtures.mr("1", draft: true), review = GLPresFixtures.mr("2", reviewers: ["bo"])
        draft.assignee = "ana"; review.assignee = "ana"
        if case .gitlabItem(var g)? = draft.providerEntity { g.assigneeLogins = ["ana"]; draft.providerEntity = .gitlabItem(g) }
        if case .gitlabItem(var g)? = review.providerEntity { g.assigneeLogins = ["ana"]; review.providerEntity = .gitlabItem(g) }
        var mine = GLPresFixtures.mr("3", assigneeLogins: ["jdoe"]); mine.assignee = "someone else"
        var notMine = GLPresFixtures.mr("4"); notMine.assignee = "bo"
        if case .gitlabItem(var g)? = notMine.providerEntity { g.assigneeLogins = ["bo"]; notMine.providerEntity = .gitlabItem(g) }
        let all = [draft, review, mine, notMine]
        func ids(_ c: GitlabMrChip) -> [String] { all.filter { c.matches($0, account: account) }.map(\.id) }
        XCTAssertEqual(ids(.allOpen), ["1", "2", "3", "4"])
        XCTAssertEqual(ids(.draft), ["1"])
        XCTAssertEqual(ids(.inReview), ["2"])
        XCTAssertEqual(ids(.assignedToMe), ["3"], "matched on assignee logins, not display names")
    }

    func testTableStateOfAnMr() {
        let c = AppTheme().colors
        func state(_ t: Ticket) -> String { gitlabMrTableState(t, palette: c).label }
        XCTAssertEqual(state(GLPresFixtures.mr("1", draft: true)), "Draft")
        XCTAssertEqual(state(GLPresFixtures.mr("2", status: .done, providerStatus: "merged")), "Merged")
        XCTAssertEqual(state(GLPresFixtures.mr("3", status: .done, providerStatus: "closed")), "Closed")
        XCTAssertEqual(state(GLPresFixtures.mr("4", reviewers: ["bo"])), "In review")
        XCTAssertEqual(state(GLPresFixtures.mr("5")), "Open")
    }

    func testSortByColumn() {
        let a = GLPresFixtures.mr("a", key: "9", title: "Zeta", updated: Date(timeIntervalSince1970: 100))
        let b = GLPresFixtures.mr("b", key: "10", title: "alpha", updated: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(gitlabSort([a, b], by: TicketSort(.id)).map(\.id), ["a", "b"], "numeric ids")
        XCTAssertEqual(gitlabSort([a, b], by: TicketSort(.id, descending: true)).map(\.id), ["b", "a"])
        XCTAssertEqual(gitlabSort([a, b], by: TicketSort(.title)).map(\.id), ["b", "a"])
        XCTAssertEqual(gitlabSort([a, b], by: .newest.toggled(.updated)).map(\.id), ["b", "a"])
    }

    // MARK: namespace tree and scope list

    func testProjectGroupsSplitPinnedRecentAndRest() {
        let ps = ["1": "icom/web/app", "2": "icom/web/api", "3": "tools/cli"].map { ProviderProject(id: $0.key, name: $0.value, accountId: "gl-a") }
            .sorted { $0.id < $1.id }
        let g = GitlabProjectGroups(projects: ps, filter: "", pinnedKeys: ["gl-a:1"], recentIds: ["2", "1"])
        XCTAssertEqual(g.pinned.map(\.id), ["1"])
        XCTAssertEqual(g.recent.map(\.id), ["2"], "a pinned project is not repeated under Recent")
        XCTAssertEqual(g.rest.map(\.id), ["2", "3"])
        XCTAssertEqual(GitlabProjectGroups(projects: ps, filter: " CLI ", pinnedKeys: [], recentIds: []).rest.map(\.id), ["3"])
    }

    func testGroupCountAggregatesSubgroups() {
        let ps = [ProviderProject(id: "1", name: "icom/web/app", accountId: "gl-a"), ProviderProject(id: "2", name: "icom/api", accountId: "gl-a")]
        let tree = GitLabProjectTree.build(ps)
        XCTAssertEqual(tree.rootGroups.map(\.name), ["icom"])
        XCTAssertEqual(gitlabGroupCount(tree.rootGroups[0]) { ["1": 3, "2": 2][$0] ?? 0 }, 5)
        let tickets = [GLPresFixtures.mr("1"), GLPresFixtures.mr("2", status: .done), GLPresFixtures.issue("3", projectId: 7, path: "x/y")]
        XCTAssertEqual(gitlabOpenCount(tickets, accountId: "gl-a", projectId: "12"), 1)
    }

    // MARK: wording and parsing helpers

    func testHumanizeMergeState() {
        XCTAssertEqual(humanizeMergeState("need_rebase"), "Need rebase")
        XCTAssertEqual(humanizeMergeState("ci_still_running"), "Ci still running")
        XCTAssertEqual(humanizeMergeState(nil), "")
        XCTAssertEqual(humanizeMergeState("  "), "")
    }

    func testTemplateRunsKeepTranslatorWordOrder() {
        let runs = templateRuns(slots: 3) { "\($0[1]) is merged into \($0[2]) by \($0[0])" }
        XCTAssertEqual(runs.map(\.slot), [1, nil, 2, nil, 0])
        XCTAssertEqual(runs.compactMap { $0.slot == nil ? $0.text : nil }, [" is merged into ", " by "])
        XCTAssertEqual(templateRuns(slots: 0) { _ in "plain" }, [TemplateRun(text: "plain", slot: nil)])
    }

    func testWebURLsFollowTheSectionAndScope() {
        let a = account
        XCTAssertEqual(gitlabWebURL(account: a, location: ToolLocation(section: GitlabSections.mrs))?.absoluteString,
                       "https://gitlab.example.com/dashboard/merge_requests")
        XCTAssertEqual(gitlabWebURL(account: a, location: ToolLocation(section: GitlabSections.issues, scopeId: "icom/web/app"))?.absoluteString,
                       "https://gitlab.example.com/icom/web/app/-/issues")
        var bare = a; bare.baseUrl = nil
        XCTAssertEqual(gitlabWebURL(account: bare, location: ToolLocation(section: GitlabSections.mrs, scopeId: "g/p"))?.absoluteString,
                       "https://gitlab.com/g/p/-/merge_requests")
        var slash = a; slash.baseUrl = "https://gl.test/"
        XCTAssertEqual(gitlabWebURL(account: slash, location: ToolLocation(section: GitlabSections.issues))?.absoluteString, "https://gl.test/dashboard/issues")
    }

    func testBreadcrumbProjectURLIsTheMrUrlBeforeTheDash() {
        XCTAssertEqual(GitlabMrBreadcrumb.projectURL("https://h/group/web/-/merge_requests/42"), "https://h/group/web")
        XCTAssertNil(GitlabMrBreadcrumb.projectURL("https://h/group/web/merge_requests/42"))
        XCTAssertNil(GitlabMrBreadcrumb.projectURL(nil))
    }

    // MARK: editors

    func testUserSelectionRules() {
        let users = [ProviderUser(account: "ana", displayName: "Ana Lopez"), ProviderUser(account: "bo", displayName: "Bo")]
        XCTAssertEqual(GitlabUserSelection.initial(users: users, current: ["Ana Lopez", "bo"]), ["ana", "bo"])
        XCTAssertEqual(GitlabUserSelection.visible(users, query: " LOP ").map(\.account), ["ana"])
        XCTAssertEqual(GitlabUserSelection.toggled(["ana"], "bo", multiple: true), ["ana", "bo"])
        XCTAssertEqual(GitlabUserSelection.toggled(["ana", "bo"], "bo", multiple: true), ["ana"])
        XCTAssertEqual(GitlabUserSelection.toggled(["ana"], "bo", multiple: false), ["bo"])
    }

    func testLabelAndMilestoneSelectionRules() {
        let labels = [ProviderLabelOption(name: "bug"), ProviderLabelOption(name: "ui"), ProviderLabelOption(name: "backend")]
        XCTAssertEqual(GitlabLabelSelection.visible(labels, query: "B").map(\.name), ["bug", "backend"])
        XCTAssertEqual(GitlabLabelSelection.ordered(["ui", "gone", "bug"], options: labels), ["bug", "ui", "gone"])
        let ms = [ProviderMilestoneOption(id: 1, title: "v1.0"), ProviderMilestoneOption(id: 2, title: "v2.0")]
        XCTAssertEqual(GitlabMilestoneEditor.visible(ms, query: "2").map(\.id), [2])
    }

    func testTimeTrackingInputBlanksBecomeNil() {
        let a = GitlabTimeTrackingInput(estimate: "  2h 30m ", spent: "   ", resetEstimate: false, resetSpent: true)
        XCTAssertEqual(a, GitlabTimeTrackingInput(estimate: "2h 30m", spent: "", resetEstimate: false, resetSpent: true))
        XCTAssertNil(a.spent)
        XCTAssertEqual(a.estimate, "2h 30m")
    }

    func testConfirmationsWordTheirDialogs() {
        let merge = GitlabMrConfirm.merge(squash: true, removeSourceBranch: true)
        XCTAssertEqual(merge.title("42"), "Merge !42?")
        XCTAssertTrue(merge.message(source: "feat", target: "main").contains("feat into main"))
        XCTAssertTrue(merge.message(source: "feat", target: "main").contains("squashed"))
        XCTAssertFalse(GitlabMrConfirm.merge(squash: false, removeSourceBranch: false).message(source: nil, target: nil).contains("squashed"))
        XCTAssertTrue(GitlabMrConfirm.close.destructive)
        XCTAssertFalse(GitlabMrConfirm.rebase.destructive)
        XCTAssertEqual(merge.action, .merge(squash: true, removeSourceBranch: true))
        XCTAssertEqual(GitlabMrConfirm.rebase.confirmLabel, "Rebase")
    }
}
