import CoreDomain
import CoreTools
import XCTest
@testable import ToolGitLab

/// `GitlabContext`, the project list, the section model, the action runner and the module surface, with fakes at the
/// service / repository boundary.
@MainActor
final class PresentationContextTests: XCTestCase {
    private func project(_ id: String, _ name: String? = nil) -> ProviderProject { ProviderProject(id: id, name: name ?? "g/p\(id)", accountId: "gl-a") }

    func testBoardsDefaultToMergeRequests() {
        // gitlab_default_kind_test.dart: the module opens on its merge-request section.
        let (ctx, _, _, _) = GLPresFixtures.context()
        let module = GitlabModule(services: ctx.services, nav: ctx.nav, registry: ctx.registry, mrService: GLPresMrService())
        XCTAssertEqual(module.defaultSection, GitlabSections.mrs)
        XCTAssertEqual(ctx.nav.location(for: "gl-a").section, GitlabSections.mrs)
    }

    func testSelectingAProjectScopesTheLocation() {
        let (ctx, _, _, _) = GLPresFixtures.context()
        ctx.selectProject(project("12"))
        XCTAssertEqual(ctx.nav.location(for: "gl-a").scopeId, "12")
        XCTAssertEqual(ctx.nav.location(for: "gl-a").recentScopeIds, ["12"])
        XCTAssertEqual(ctx.selection, GitlabProjectSelection(accountId: "gl-a", projectId: "12", projectName: "g/p12"))
        ctx.selectAssignedToMe(accountId: "gl-a")
        XCTAssertEqual(ctx.nav.location(for: "gl-a").quickScope, .assignedToMe)
        ctx.selectAll(accountId: "gl-a")
        XCTAssertNil(ctx.nav.location(for: "gl-a").scopeId)
        XCTAssertEqual(ctx.nav.location(for: "gl-a").quickScope, QuickScope.none)
        XCTAssertNil(ctx.selection)
    }

    func testSliceSyncFetchesTheSelectedProjectAndKind() async {
        let (ctx, _, _, service) = GLPresFixtures.context()
        await ctx.syncSlice(kind: .mergeRequest)
        XCTAssertTrue(service.calls.isEmpty, "nothing selected, nothing fetched")
        ctx.selectProject(project("12"))
        await ctx.syncSlice(kind: .mergeRequest)
        await ctx.syncSlice(kind: .issue)
        XCTAssertEqual(service.calls, ["slice:gl-a:12:mr", "slice:gl-a:12:issue"])
        XCTAssertFalse(ctx.sliceLoading)
        XCTAssertNil(ctx.sliceError)
        ctx.selectMine(accountId: "gl-a")
        await ctx.syncSlice(kind: .mergeRequest)
        XCTAssertEqual(service.calls.last, "mine:gl-a")
    }

    func testSliceFailureIsReportedAndRefreshChangesTheKey() async {
        let (ctx, _, _, service) = GLPresFixtures.context()
        service.failWith = .network("offline")
        ctx.selectProject(project("12"))
        let key = ctx.sliceKey(kind: .issue)
        await ctx.syncSlice(kind: .issue)
        XCTAssertEqual(ctx.sliceError, "offline")
        ctx.refreshSlice()
        XCTAssertNotEqual(ctx.sliceKey(kind: .issue), key)
        XCTAssertNotEqual(ctx.sliceKey(kind: .issue), ctx.sliceKey(kind: .mergeRequest))
    }

    func testSliceErrorClearsWhenNothingIsSelectedAnymore() async {
        let (ctx, _, _, service) = GLPresFixtures.context()
        service.failWith = .network("offline")
        ctx.selectProject(project("12"))
        await ctx.syncSlice(kind: .issue)
        XCTAssertEqual(ctx.sliceError, "offline")
        ctx.selectAll(accountId: "gl-a")
        await ctx.syncSlice(kind: .issue)
        XCTAssertNil(ctx.sliceError, "the banner must not outlive the project it was about")
    }

    func testGroupsStartExpandedAndToggle() {
        let (ctx, _, _, _) = GLPresFixtures.context()
        XCTAssertTrue(ctx.collapsedGroups.isEmpty)
        ctx.toggleGroup("gl-a:icom")
        XCTAssertEqual(ctx.collapsedGroups, ["gl-a:icom"])
        ctx.toggleGroup("gl-a:icom")
        XCTAssertTrue(ctx.collapsedGroups.isEmpty)
    }

    func testPinningWritesTheSettings() async throws {
        let (ctx, _, settings, _) = GLPresFixtures.context()
        ctx.togglePinnedProject("gl-a:12")
        XCTAssertTrue(ctx.pinnedProjects.contains("gl-a:12"))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(settings.current.pinnedProjects, ["gl-a:12"])
        ctx.togglePinnedProject("gl-a:12")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(settings.current.pinnedProjects, [])
    }

    func testViewModeIsRememberedAndLocationWins() async throws {
        let (ctx, _, settings, _) = GLPresFixtures.context()
        XCTAssertEqual(ctx.viewMode(accountId: "gl-a", section: GitlabSections.mrs, fallback: "open"), "open")
        ctx.rememberViewMode("merged", section: GitlabSections.mrs, accountId: "gl-a")
        XCTAssertEqual(ctx.viewMode(accountId: "gl-a", section: GitlabSections.mrs, fallback: "open"), "merged")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(settings.current.viewModes["gitlab.mrs"], "merged")
    }

    func testProjectListLoadsFreshAndKeepsCacheOnFailure() async {
        let service = GLPresMrService()
        service.projects = [project("1")]
        let cachedOld = ProviderProject(id: "9", name: "old/one", accountId: "gl-a")
        let model = GitlabProjectsModel(accountId: "gl-a", service: service) { _ in [cachedOld] }
        XCTAssertEqual(model.phase, .loading)
        await model.load()
        XCTAssertEqual(model.projects.map(\.id), ["1"])
        service.failWith = .network("down")
        await model.reload()
        XCTAssertEqual(model.projects.map(\.id), ["1"], "a failed refresh keeps what was shown")

        let failing = GLPresMrService(); failing.failWith = .network("down")
        let bare = GitlabProjectsModel(accountId: "gl-a", service: failing)
        await bare.load()
        XCTAssertEqual(bare.phase, .failed("down"))
        let cached = GitlabProjectsModel(accountId: "gl-a", service: failing) { _ in [cachedOld] }
        await cached.load()
        XCTAssertEqual(cached.projects.map(\.id), ["9"], "a cached list masks the failure")
    }

    func testSectionModelScopesFiltersAndBuildsColumns() async throws {
        let store = GLPresStore()
        var mine = GLPresFixtures.mr("5"); mine.assignee = "jdoe"
        if case .gitlabItem(var g)? = mine.providerEntity { g.assigneeLogins = ["jdoe"]; g.assignees = ["jdoe"]; mine.providerEntity = .gitlabItem(g) }
        store.tickets = [GLPresFixtures.mr("1"), GLPresFixtures.mr("2", status: .done, providerStatus: "merged"),
                         GLPresFixtures.mr("3", status: .done, providerStatus: "closed", projectId: 7, path: "other/repo"),
                         GLPresFixtures.mr("4", providerStatus: "draft", draft: true), GLPresFixtures.issue("6"), mine]
        store.accounts = [GLPresFixtures.account]
        let (ctx, _, _, _) = GLPresFixtures.context(store: store)
        let model = GitlabSectionModel(ctx: ctx, account: GLPresFixtures.account, kind: .mergeRequest)
        model.start()
        try await Task.sleep(for: .milliseconds(150))
        model.installScope(scopeId: nil, assignedToMe: false)
        XCTAssertEqual(Set(model.filtered.map(\.id)), ["1", "2", "3", "4", "5"], "issues are not merge requests")
        XCTAssertEqual(model.listRows(state: .open, chip: .allOpen).map(\.id).sorted(), ["1", "4", "5"])
        XCTAssertEqual(model.listRows(state: .merged, chip: .allOpen).map(\.id), ["2"])
        XCTAssertEqual(model.listRows(state: .open, chip: .draft).map(\.id), ["4"])
        XCTAssertEqual(model.mrBoard.column(.draft).tickets.map(\.id), ["4"])
        XCTAssertEqual(model.mrBoard.column(.merged).tickets.map(\.id), ["2"])
        XCTAssertEqual(model.mrBoard.column(.closed).tickets.map(\.id), ["3"])
        model.installScope(scopeId: "12", assignedToMe: false)
        XCTAssertEqual(Set(model.filtered.map(\.id)), ["1", "2", "4", "5"])
        model.installScope(scopeId: nil, assignedToMe: true)
        XCTAssertEqual(model.filtered.map(\.id), ["5"])
        XCTAssertEqual(model.board.facetScope, .gitlabMergeRequest)
        model.board.stop()

        let issues = GitlabSectionModel(ctx: ctx, account: GLPresFixtures.account, kind: .issue)
        issues.start()
        try await Task.sleep(for: .milliseconds(150))
        issues.installScope(scopeId: nil, assignedToMe: false)
        XCTAssertEqual(issues.filtered.map(\.id), ["6"], "only issues, not merge requests")
        XCTAssertEqual(issues.issueBoard.column(.open).tickets.map(\.id), ["6"])
        XCTAssertEqual(issues.board.facetScope, .none)
        issues.board.stop()
    }

    func testActionRunnerRunsEachActionAndWordsTheToast() async {
        let service = GLPresMrService()
        let runner = GitlabActionRunner(service: service)
        let t = GLPresFixtures.mr("7")
        let actions: [GitlabMrAction] = [.approve, .unapprove, .rebase, .close, .reopen, .merge(squash: true, removeSourceBranch: false), .setDraft(true), .setDraft(false)]
        for a in actions { _ = await runner.perform(a, t) }
        XCTAssertEqual(service.calls, ["approve:7", "unapprove:7", "rebase:7", "close:7", "reopen:7", "merge:7:squash=true:remove=false", "draft:7:true", "draft:7:false"],
                       "merging sends the chosen options")
        XCTAssertEqual(runner.successMessage(.approve, t), "Approved !7")
        XCTAssertEqual(runner.successMessage(.unapprove, t), "Revoked approval on !7")
        XCTAssertEqual(runner.successMessage(.merge(squash: false, removeSourceBranch: false), t), "Merged !7")
        XCTAssertEqual(runner.successMessage(.rebase, t), "Rebased !7")
        XCTAssertEqual(runner.successMessage(.close, t), "Closed merge request !7")
        XCTAssertEqual(runner.successMessage(.reopen, t), "Reopened merge request !7")
        XCTAssertEqual(runner.successMessage(.setDraft(true), t), "Marked !7 as draft")
        XCTAssertEqual(runner.successMessage(.setDraft(false), t), "Marked !7 as ready")
        XCTAssertEqual(GitlabActionRunner.failureMessage(.network("boom")), "Failed: boom")
        XCTAssertEqual(GitlabActionRunner.failureMessage(.network("")), "Failed: Provider action failed")
        service.failWith = .validation("not mergeable")
        let res = await runner.perform(.approve, t)
        XCTAssertEqual(res.failure, .validation("not mergeable"))
        XCTAssertEqual(GitlabMrAction.merge(squash: true, removeSourceBranch: true).kind, .merge)
        XCTAssertEqual(GitlabMrAction.setDraft(false).kind, .draft)
    }

    func testDetailModelWatchesCommentsAndActivity() async throws {
        let store = GLPresStore()
        store.comments = [Comment(id: "c1", ticketId: "7", authorName: "ana", body: "hi", createdAt: Date()),
                          Comment(id: "c2", ticketId: "other", authorName: "bo", body: "x", createdAt: Date())]
        store.events = [ActivityEvent(id: "e1", ticketId: "7", actor: "ana", action: "assigned", at: Date())]
        let (ctx, _, _, _) = GLPresFixtures.context(store: store)
        let model = GitlabMrDetailModel(ticketId: "7", services: ctx.services)
        let task = Task { await model.run() }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.comments.map(\.id), ["c1"])
        XCTAssertEqual(model.activity.map(\.id), ["e1"])
        task.cancel()
    }

    func testModuleSurface() async throws {
        let store = GLPresStore()
        store.tickets = [GLPresFixtures.mr("1"), GLPresFixtures.mr("2", status: .done, providerStatus: "merged"), GLPresFixtures.issue("3")]
        let registry = ToolRegistry()
        let (ctx, _, _, _) = GLPresFixtures.context(store: store, registry: registry)
        let service = GLPresMrService()
        service.projects = [project("12", "icom/web/app"), project("13")]
        let module = GitlabModule(services: ctx.services, nav: ctx.nav, registry: registry, mrService: service)
        registry.register(module)
        XCTAssertEqual(registry.module(for: .gitlab)?.providerType, .gitlab)
        XCTAssertEqual(module.defaultSection, "gitlab.mrs")
        XCTAssertEqual(module.sections.map(\.id), ["gitlab.mrs", "gitlab.issues", "gitlab.pipelines"])
        XCTAssertEqual(module.sections.map(\.available), [true, true, false])
        XCTAssertEqual(module.sections[0].viewModes.map(\.id), ["open", "merged", "closed", "board"])
        XCTAssertEqual(module.sections[1].viewModes.map(\.id), ["list", "board"])
        XCTAssertEqual(module.sections.map(\.scopeKind), [.repository, .repository, .none])
        XCTAssertEqual(module.roleLabel, "Code hosting & CI")

        // buildDetail only for merge requests
        XCTAssertNotNil(module.buildDetail(ticket: GLPresFixtures.mr("1")) {})
        XCTAssertNil(module.buildDetail(ticket: GLPresFixtures.issue("3")) {})
        XCTAssertNotNil(module.buildActions(ticket: GLPresFixtures.issue("3")))
        XCTAssertNotNil(module.buildDetailSidebar(ticket: GLPresFixtures.issue("3")))
        var plain = GLPresFixtures.issue("9"); plain.providerEntity = nil
        XCTAssertNil(module.buildDetailSidebar(ticket: plain))

        // scopeTickets follows the account on screen
        ctx.nav.select(.account("gl-a"))
        var other = GLPresFixtures.mr("x"); other.accountId = "gl-b"
        let scoped = module.scopeTickets(location: ToolLocation(section: "gitlab.mrs", scopeId: "12"), tickets: store.tickets + [other])
        XCTAssertEqual(scoped.map(\.id).sorted(), ["1", "2", "3"])

        var titles: [String?] = []
        for await v in module.scopeTitle(account: GLPresFixtures.account, location: ToolLocation(section: "gitlab.mrs", scopeId: "12"))! { titles.append(v) }
        XCTAssertEqual(titles.last ?? nil, "icom/web/app", "the project name once the list is known")
        XCTAssertNil(module.scopeTitle(account: GLPresFixtures.account, location: ToolLocation(section: "gitlab.mrs")))

        var latest: ToolMetrics?
        for await m in module.metrics(account: GLPresFixtures.account) { latest = m; if m?.primaryCount == 2 && m?.secondaryCount == 1 { break } }
        XCTAssertEqual(latest?.primaryCount, 2, "the project count")
        XCTAssertEqual(latest?.secondaryCount, 1, "open merge requests")
        XCTAssertEqual(latest?.primaryLabel, "All projects")
        XCTAssertEqual(latest?.secondaryLabel, "Merge Requests")
    }
}
