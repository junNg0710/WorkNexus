import CoreDomain
import XCTest
@testable import SharedKit

/// Ported from: test/domain/derive_board_facets_test.dart, count_assigned_to_me_test.dart
final class FacetsAndCountsTests: XCTestCase {
    private let derive = DeriveBoardFacets()

    private func bug(_ id: String, assignee: String? = nil, severity: Int? = nil, priority: Priority = .medium, bugType: String? = nil,
                     resolution: String? = nil, providerStatus: String = "active", resolvedBy: String? = nil, openedBy: String? = nil,
                     confirmed: Int? = nil, module: String? = nil) -> Ticket {
        let hasEntity = bugType != nil || resolution != nil || resolvedBy != nil || openedBy != nil || confirmed != nil || module != nil
        return makeTicket(id, account: "ztB", project: "p", provider: .zentao, key: id, providerStatus: providerStatus, priority: priority,
                          labels: resolution.map { ["resolution:\($0)"] } ?? [], severity: severity, assignee: assignee, type: "Bug",
                          entity: hasEntity ? .zentaoBug(ZenTaoBugEntity(module: module, bugType: bugType, confirmed: confirmed,
                                                                           resolution: resolution, openedBy: openedBy, resolvedBy: resolvedBy)) : nil)
    }
    private func mr(_ id: String, assignees: [String], reviewers: [String], priority: Priority = .medium) -> Ticket {
        makeTicket(id, account: "gl", project: "p", provider: .gitlab, key: id, status: .review, providerStatus: "opened", priority: priority,
                   assignee: assignees.first, type: "MergeRequest", entity: .gitlabItem(GitLabItemEntity(reviewers: reviewers, assignees: assignees)))
    }
    private func group(_ f: BoardFacets, _ k: BoardFacetKind) -> BoardFacetGroup { f.groups.first { $0.kind == k }! }

    func testBugScopeDerivesGroups() {
        let f = derive(BoardFacetsInput(tickets: [
            bug("1", assignee: "Terry", severity: 1, priority: .urgent, bugType: "codeerror", resolution: "fixed"),
            bug("2", assignee: "Thanh", severity: 3, priority: .high, bugType: "config"),
            bug("3", assignee: "Terry", severity: 1, priority: .high, bugType: "codeerror", resolution: "duplicate"),
        ], scope: .bug))
        XCTAssertEqual(f.groups.map(\.kind), [.assignee, .severity, .priority, .bugType, .resolution])
        XCTAssertEqual(group(f, .assignee).options.first?.value, "Terry")
        XCTAssertEqual(group(f, .assignee).options.first?.count, 2)
        XCTAssertEqual(Set(group(f, .priority).options.map(\.value)), ["urgent", "high"])
    }

    func testDropsSingleValueGroups() {
        let f = derive(BoardFacetsInput(tickets: [bug("1", assignee: "Terry", severity: 1, priority: .high),
                                                  bug("2", assignee: "Thanh", severity: 1, priority: .high)], scope: .bug))
        XCTAssertEqual(f.groups.map(\.kind), [.assignee])
    }

    func testUnassignedUsesEmptyStringValue() {
        let f = derive(BoardFacetsInput(tickets: [bug("1", assignee: "Terry", severity: 1), bug("2", severity: 2)], scope: .bug))
        XCTAssertTrue(group(f, .assignee).options.map(\.value).contains(""))
    }

    func testTaskScopeLimitsToAssigneeAndPriority() {
        let f = derive(BoardFacetsInput(tickets: [bug("1", assignee: "A", priority: .urgent), bug("2", assignee: "B", priority: .low)], scope: .task))
        XCTAssertEqual(f.groups.map(\.kind), [.assignee, .priority])
    }

    func testGitLabMergeRequestScope() {
        let f = derive(BoardFacetsInput(tickets: [
            mr("1", assignees: ["Thanh"], reviewers: ["Terry"], priority: .urgent),
            mr("2", assignees: ["Terry"], reviewers: ["Thanh"], priority: .low),
            mr("3", assignees: ["Thanh"], reviewers: ["Terry"], priority: .low),
        ], scope: .gitlabMergeRequest))
        XCTAssertEqual(f.groups.map(\.kind), [.assignee, .reviewer, .priority])
        XCTAssertEqual(group(f, .assignee).options.first?.value, "Thanh")
        XCTAssertEqual(group(f, .reviewer).options.first?.value, "Terry")
    }

    func testBugScopeAddsStatusResolverReporterConfirmation() {
        let f = derive(BoardFacetsInput(tickets: [
            bug("1", openedBy: "Ryan", confirmed: 1),
            bug("2", resolution: "fixed", providerStatus: "resolved", resolvedBy: "Thanh", openedBy: "Cat", confirmed: 1),
            bug("3", providerStatus: "closed", resolvedBy: "Luci", openedBy: "Ryan", confirmed: 0),
        ], scope: .bug))
        let kinds = f.groups.map(\.kind)
        let wanted: [BoardFacetKind] = [.resolvedBy, .openedBy, .status, .confirmed]
        XCTAssertEqual(kinds.filter(wanted.contains), wanted)    // people first, then status; confirmation last
        XCTAssertEqual(group(f, .status).options.map(\.value), ["confirmedToFix", "resolvedVerify", "closed"])
        XCTAssertEqual(Set(group(f, .resolvedBy).options.map(\.value)), ["Thanh", "Luci"])
        XCTAssertEqual(group(f, .openedBy).options.first?.value, "Ryan")
        XCTAssertEqual(Set(group(f, .confirmed).options.map(\.value)), ["1", "0"])
    }

    func testNoneScopeYieldsNoGroups() { XCTAssertTrue(derive(BoardFacetsInput(tickets: [], scope: .none)).groups.isEmpty) }

    func testCatalogListsEveryChoiceWithZeroCounts() {
        let f = derive(BoardFacetsInput(tickets: [bug("1", severity: 2), bug("2", severity: 2)], scope: .bug,
                                        catalog: BoardFacetCatalog([.severity: [BoardFacetChoice("1"), BoardFacetChoice("2"), BoardFacetChoice("3")]])))
        let s = group(f, .severity)
        XCTAssertEqual(s.options.map(\.value), ["1", "2", "3"]); XCTAssertEqual(s.options.map(\.count), [0, 2, 0])
    }

    func testCatalogKeepsDimensionWithOneValueAndAddsUnknownAfterIt() {
        let one = derive(BoardFacetsInput(tickets: [bug("1", assignee: "thanh")], scope: .bug,
                                          catalog: BoardFacetCatalog([.assignee: [BoardFacetChoice("thanh", label: "Thanh Nguyen"), BoardFacetChoice("an", label: "An Le")]])))
        XCTAssertEqual(group(one, .assignee).options.map(\.label), ["Thanh Nguyen", "An Le"])
        XCTAssertEqual(group(one, .assignee).options.first?.count, 1)
        let extra = derive(BoardFacetsInput(tickets: [bug("1", assignee: "guest"), bug("2", assignee: "thanh")], scope: .bug,
                                            catalog: BoardFacetCatalog([.assignee: [BoardFacetChoice("thanh")]])))
        XCTAssertEqual(group(extra, .assignee).options.map(\.value), ["thanh", "guest"])
    }

    func testModulesListFirstAndNeedNames() {
        let tickets = [bug("1", module: "12"), bug("2", module: "12"), bug("3", module: "0")]
        let f = derive(BoardFacetsInput(tickets: tickets, scope: .bug,
                                        catalog: BoardFacetCatalog([.module: [BoardFacetChoice("12", label: "Live stream"), BoardFacetChoice("13", label: "Share")]])))
        XCTAssertEqual(f.groups.first?.kind, .module)
        XCTAssertEqual(group(f, .module).options.map(\.label), ["Live stream", "Share"]); XCTAssertEqual(group(f, .module).options.map(\.count), [2, 0])
        let bare = derive(BoardFacetsInput(tickets: [bug("1", module: "12"), bug("2", module: "13")], scope: .bug, catalog: BoardFacetCatalog([:])))
        XCTAssertFalse(bare.groups.contains { $0.kind == .module })
    }

    func testFacetActiveReadsTheMatchingFilterSet() {
        var f = FilterState(); f.severities = [2]; f.priorities = [.high]; f.zentaoStatuses = ["closed"]
        XCTAssertTrue(facetActive(f, .severity, "2")); XCTAssertFalse(facetActive(f, .severity, "1"))
        XCTAssertTrue(facetActive(f, .priority, "high")); XCTAssertFalse(facetActive(f, .priority, "nope"))
        XCTAssertTrue(facetActive(f, .status, "closed"))
    }

    // MARK: CountAssignedToMe
    private let zentao = Account(id: "z", workspaceId: "w", providerType: .zentao, handle: "thanh")
    private let gitlab = Account(id: "gl", workspaceId: "w", providerType: .gitlab, handle: "dyno")
    private let github = Account(id: "gh", workspaceId: "w2", providerType: .github, handle: "octo")

    private func t(_ id: String, _ account: Account, _ type: String, _ entity: TicketProviderEntity, assignee: String? = nil,
                   status: UnifiedStatus = .todo, raw: String = "active") -> Ticket {
        Ticket(id: "\(account.id):\(id)", accountId: account.id, projectId: "\(account.id):p", providerType: account.providerType, externalKey: id,
               title: id, body: "", priority: .medium, status: status, providerStatus: raw, sourceHash: "", externalType: type, assignee: assignee,
               providerEntity: entity)
    }
    private func zbug(_ id: String, _ product: String, assignee: String? = "thanh") -> Ticket {
        t(id, zentao, "bug", .zentaoBug(ZenTaoBugEntity(product: product)), assignee: assignee)
    }
    private func ztask(_ id: String, _ execution: String, _ project: String) -> Ticket {
        t(id, zentao, "task", .zentaoTask(ZenTaoTaskEntity(execution: execution, project: project)), assignee: "Thanh ")
    }

    func testZenTaoRollsUpThroughGroups() {
        var resolved = zbug("5", "10"); resolved.status = .review; resolved.providerStatus = "resolved"
        let c = CountAssignedToMe()(tickets: [zbug("1", "10"), zbug("2", "10"), zbug("3", "11"), zbug("4", "10", assignee: "someone"), resolved,
                                              ztask("6", "100", "7"), ztask("8", "101", "7")], accounts: [zentao, gitlab, github])
        XCTAssertEqual(c.zentaoProduct("z", "10"), 2); XCTAssertEqual(c.zentaoProduct("z", "11"), 1); XCTAssertEqual(c.zentaoBugs("z"), 3)
        XCTAssertEqual(c.zentaoExecution("z", "100"), 1); XCTAssertEqual(c.zentaoProject("z", "7"), 2); XCTAssertEqual(c.zentaoTasks("z"), 2)
        XCTAssertEqual(c.pinned("z"), 0); XCTAssertEqual(c.account("z"), 5); XCTAssertEqual(c.workspace("w"), 5); XCTAssertEqual(c.total, 5)
    }

    func testPinnedLeavesCountTowardPinnedNotTheirGroup() {
        let c = CountAssignedToMe()(tickets: [zbug("1", "10"), zbug("2", "11"), ztask("3", "100", "7")], accounts: [zentao, gitlab, github],
                                    pinnedProjects: ["z:10"], pinnedExecutions: ["z:100"])
        XCTAssertEqual(c.zentaoProduct("z", "10"), 1); XCTAssertEqual(c.zentaoExecution("z", "100"), 1); XCTAssertEqual(c.pinned("z"), 2)
        XCTAssertEqual(c.zentaoBugs("z"), 1); XCTAssertEqual(c.zentaoTasks("z"), 0); XCTAssertEqual(c.zentaoProject("z", "7"), 0); XCTAssertEqual(c.account("z"), 3)
    }

    func testGitLabAndGitHubMatchTheLogin() {
        let c = CountAssignedToMe()(tickets: [
            t("mr1", gitlab, "MergeRequest", .gitlabItem(GitLabItemEntity(projectId: 5, assignees: ["Dyno Nguyen"], assigneeLogins: ["dyno"])), assignee: "Dyno Nguyen"),
            t("i1", gitlab, "Issue", .gitlabItem(GitLabItemEntity(projectId: 6, assigneeLogins: ["someone", "dyno"])), assignee: "Dyno Nguyen"),
            t("i2", gitlab, "Issue", .gitlabItem(GitLabItemEntity(projectId: 6, assigneeLogins: ["other"])), assignee: "Other"),
            t("pr1", github, "PullRequest", .githubItem(GitHubItemEntity(repo: "o/r")), assignee: "octo"),
            t("pr2", github, "PullRequest", .githubItem(GitHubItemEntity(repo: "o/r")), assignee: "Octo Cat", status: .done, raw: "merged"),
        ], accounts: [zentao, gitlab, github], pinnedProjects: ["gl:5"])
        XCTAssertEqual(c.project("gl", "5"), 1); XCTAssertEqual(c.project("gl", "6"), 1); XCTAssertEqual(c.pinned("gl"), 1)
        XCTAssertEqual(c.projects("gl"), 1); XCTAssertEqual(c.account("gl"), 2); XCTAssertEqual(c.project("gh", "o/r"), 1)
        XCTAssertEqual(c.account("gh"), 1); XCTAssertEqual(c.workspace("w"), 2); XCTAssertEqual(c.workspace("w2"), 1); XCTAssertEqual(c.total, 3)
    }

    func testUnknownAccountsAreNotCounted() { XCTAssertEqual(CountAssignedToMe()(tickets: [zbug("1", "10")], accounts: []).total, 0) }
}
