import CoreDomain
import CoreTools
import XCTest
@testable import ToolGitHub

/// `GithubContext`, the repo list, the section model, the action runner and the module surface, with fakes at the
/// service / repository boundary.
@MainActor
final class PresentationContextTests: XCTestCase {
    private func repo(_ id: String) -> ProviderProject { ProviderProject(id: id, name: id, accountId: "gh-a") }

    func testSelectingARepoScopesTheLocationAndLeavesReviewRequested() {
        let (ctx, _, _, _) = PresFixtures.context()
        ctx.setReviewRequested(true, accountId: "gh-a")
        ctx.selectRepo(repo("acme/web"))
        XCTAssertEqual(ctx.nav.location(for: "gh-a").scopeId, "acme/web")
        XCTAssertEqual(ctx.selection, GithubRepoSelection(accountId: "gh-a", repoId: "acme/web", repoName: "acme/web"))
        XCTAssertFalse(ctx.isReviewRequested("gh-a"))
        ctx.selectAll(accountId: "gh-a")
        XCTAssertNil(ctx.nav.location(for: "gh-a").scopeId)
        XCTAssertNil(ctx.selection)
    }

    func testOpeningARepoBoardSwitchesToIssues() {
        let (ctx, _, _, _) = PresFixtures.context()
        ctx.openRepoBoard(repo("acme/web"))
        XCTAssertEqual(ctx.nav.state.rail, .account("gh-a"))
        XCTAssertEqual(ctx.nav.location(for: "gh-a").section, GithubSections.issues)
        XCTAssertEqual(ctx.selection?.repoId, "acme/web")
    }

    func testSliceSyncFetchesTheSelectedRepoAndKind() async {
        let (ctx, _, _, service) = PresFixtures.context()
        await ctx.syncSlice(kind: .pullRequest)
        XCTAssertTrue(service.calls.isEmpty, "nothing selected, nothing fetched")
        ctx.selectRepo(repo("acme/web"))
        await ctx.syncSlice(kind: .pullRequest)
        await ctx.syncSlice(kind: .issue)
        XCTAssertEqual(service.calls, ["slice:gh-a:acme/web:pr", "slice:gh-a:acme/web:issue"])
        XCTAssertFalse(ctx.sliceLoading)
        XCTAssertNil(ctx.sliceError)
        ctx.selectMine(accountId: "gh-a")
        await ctx.syncSlice(kind: .pullRequest)
        XCTAssertEqual(service.calls.last, "mine:gh-a")
    }

    func testSliceFailureIsReportedAndRefreshChangesTheKey() async {
        let (ctx, _, _, service) = PresFixtures.context()
        service.failWith = .network("offline")
        ctx.selectRepo(repo("acme/web"))
        let key = ctx.sliceKey(kind: .issue)
        await ctx.syncSlice(kind: .issue)
        XCTAssertEqual(ctx.sliceError, "offline")
        ctx.refreshSlice()
        XCTAssertNotEqual(ctx.sliceKey(kind: .issue), key)
        XCTAssertNotEqual(ctx.sliceKey(kind: .issue), ctx.sliceKey(kind: .pullRequest))
    }

    func testSliceErrorClearsWhenNothingIsSelectedAnymore() async {
        let (ctx, _, _, service) = PresFixtures.context()
        service.failWith = .network("offline")
        ctx.selectRepo(repo("acme/web"))
        await ctx.syncSlice(kind: .issue)
        XCTAssertEqual(ctx.sliceError, "offline")
        ctx.selectAll(accountId: "gh-a")
        await ctx.syncSlice(kind: .issue)
        XCTAssertNil(ctx.sliceError, "the banner must not outlive the repository it was about")
    }

    func testPinningWritesTheSettings() async throws {
        let (ctx, _, settings, _) = PresFixtures.context()
        ctx.togglePinnedProject("gh-a:acme/web")
        XCTAssertTrue(ctx.pinnedProjects.contains("gh-a:acme/web"))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(settings.current.pinnedProjects, ["gh-a:acme/web"])
        ctx.togglePinnedProject("gh-a:acme/web")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(settings.current.pinnedProjects, [])
    }

    func testViewModeIsRememberedAndLocationWins() async throws {
        let (ctx, _, settings, _) = PresFixtures.context()
        XCTAssertEqual(ctx.viewMode(accountId: "gh-a", section: GithubSections.pulls, fallback: "open"), "open")
        ctx.rememberViewMode("merged", section: GithubSections.pulls, accountId: "gh-a")
        XCTAssertEqual(ctx.viewMode(accountId: "gh-a", section: GithubSections.pulls, fallback: "open"), "merged")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(settings.current.viewModes["github.pulls"], "merged")
        let (fresh, _, _, _) = PresFixtures.context()
        fresh.start()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(fresh.viewMode(accountId: "gh-a", section: GithubSections.pulls, fallback: "open"), "open")
    }

    func testRepoListLoadsFreshAndKeepsCacheOnFailure() async {
        let service = PresPrService()
        service.repos = [repo("a/b")]
        let model = GithubReposModel(accountId: "gh-a", service: service) { _ in [ProviderProject(id: "old/one", name: "old/one", accountId: "gh-a")] }
        XCTAssertEqual(model.phase, .loading)
        await model.load()
        XCTAssertEqual(model.repos.map(\.id), ["a/b"])
        service.failWith = .network("down")
        await model.reload()
        XCTAssertEqual(model.repos.map(\.id), ["a/b"], "a failed refresh keeps what was shown")

        let failing = PresPrService(); failing.failWith = .network("down")
        let bare = GithubReposModel(accountId: "gh-a", service: failing)
        await bare.load()
        XCTAssertEqual(bare.phase, .failed("down"))
        let cached = GithubReposModel(accountId: "gh-a", service: failing) { _ in [ProviderProject(id: "old/one", name: "old/one", accountId: "gh-a")] }
        await cached.load()
        XCTAssertEqual(cached.repos.map(\.id), ["old/one"], "a cached list masks the failure")
    }

    func testSectionModelScopesFiltersAndBuildsColumns() async throws {
        let store = PresStore()
        store.tickets = [PresFixtures.pr("1"), PresFixtures.pr("2", status: .done, providerStatus: "merged", merged: true),
                         PresFixtures.pr("3", status: .done, providerStatus: "closed", repo: "other/repo"),
                         PresFixtures.pr("4", providerStatus: "draft", draft: true, reviewerLogins: ["octocat"]), PresFixtures.issue("5")]
        store.accounts = [PresFixtures.account]
        let (ctx, _, _, _) = PresFixtures.context(store: store)
        let model = GithubSectionModel(ctx: ctx, account: PresFixtures.account, kind: .pullRequest)
        model.start()
        try await Task.sleep(for: .milliseconds(150))
        model.installScope(scopeId: nil, reviewRequested: false)
        XCTAssertEqual(Set(model.filtered.map(\.id)), ["1", "2", "3", "4"], "issues are not pull requests")
        XCTAssertEqual(model.listRows(state: .open).map(\.id).sorted(), ["1", "4"])
        XCTAssertEqual(model.listRows(state: .merged).map(\.id), ["2"])
        XCTAssertEqual(model.prBoard.column(.draft).tickets.map(\.id), ["4"])
        XCTAssertEqual(model.prBoard.column(.merged).tickets.map(\.id), ["2"])
        model.installScope(scopeId: "acme/web", reviewRequested: false)
        XCTAssertEqual(Set(model.filtered.map(\.id)), ["1", "2", "4"])
        model.installScope(scopeId: nil, reviewRequested: true)
        XCTAssertEqual(model.filtered.map(\.id), ["4"])
        model.board.stop()

        let issues = GithubSectionModel(ctx: ctx, account: PresFixtures.account, kind: .issue)
        issues.start()
        try await Task.sleep(for: .milliseconds(150))
        issues.installScope(scopeId: nil, reviewRequested: false)
        XCTAssertEqual(issues.filtered.map(\.id), ["5"], "only issues, not pull requests")
        XCTAssertEqual(issues.issueBoard.column(.open).tickets.map(\.id), ["5"])
        issues.board.stop()
    }

    func testActionRunnerRunsEachCommandAndWordsTheToast() async {
        let service = PresPrService()
        let runner = GithubActionRunner(service: service)
        let t = PresFixtures.pr("7")
        for c in [GithubPrCommand.merge, .updateBranch, .close, .reopen] { _ = await runner.perform(c, t) }
        XCTAssertEqual(service.calls, ["merge:7", "update:7", "close:7", "reopen:7"])
        XCTAssertEqual(runner.successMessage(.merge, t), "Merged #7")
        XCTAssertEqual(runner.successMessage(.updateBranch, t), "Updated branch for #7")
        XCTAssertEqual(runner.successMessage(.close, t), "Closed #7")
        XCTAssertEqual(runner.successMessage(.reopen, t), "Reopened #7")
        XCTAssertEqual(GithubActionRunner.failureMessage(.network("boom")), "Failed: boom")
        XCTAssertEqual(GithubActionRunner.failureMessage(.network("")), "Failed: Provider action failed")
        service.failWith = .validation("not mergeable")
        let res = await runner.perform(.merge, t)
        XCTAssertEqual(res.failure, .validation("not mergeable"))
    }

    func testDetailModelWatchesCommentsAndActivity() async throws {
        let store = PresStore()
        store.comments = [Comment(id: "c1", ticketId: "7", authorName: "ana", body: "hi", createdAt: Date()),
                          Comment(id: "c2", ticketId: "other", authorName: "bo", body: "x", createdAt: Date())]
        store.events = [ActivityEvent(id: "e1", ticketId: "7", actor: "ana", action: "assigned", at: Date())]
        let (ctx, _, _, _) = PresFixtures.context(store: store)
        let model = GithubPrDetailModel(ticketId: "7", services: ctx.services)
        let task = Task { await model.run() }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.comments.map(\.id), ["c1"])
        XCTAssertEqual(model.activity.map(\.id), ["e1"])
        task.cancel()
    }

    func testModuleSurface() async throws {
        let store = PresStore()
        store.tickets = [PresFixtures.pr("1"), PresFixtures.pr("2", status: .done, providerStatus: "merged", merged: true), PresFixtures.issue("3"), PresFixtures.issue("4")]
        let registry = ToolRegistry()
        let (ctx, _, _, _) = PresFixtures.context(store: store, registry: registry)
        let module = GithubModule(services: ctx.services, nav: ctx.nav, registry: registry, prService: PresPrService())
        registry.register(module)
        XCTAssertEqual(registry.module(for: .github)?.providerType, .github)
        XCTAssertEqual(module.providerType, .github)
        XCTAssertEqual(module.defaultSection, "github.pulls")
        XCTAssertEqual(module.sections.map(\.id), ["github.pulls", "github.issues", "github.actions"])
        XCTAssertEqual(module.sections.map(\.available), [true, true, false])
        XCTAssertEqual(module.sections[0].viewModes.map(\.id), ["open", "merged", "closed", "board"])
        XCTAssertEqual(module.sections[1].viewModes.map(\.id), ["list", "board"])
        XCTAssertEqual(module.sections.map(\.scopeKind), [.repository, .repository, .none])

        // buildDetail only for pull requests
        XCTAssertNotNil(module.buildDetail(ticket: PresFixtures.pr("1")) {})
        XCTAssertNil(module.buildDetail(ticket: PresFixtures.issue("3")) {})
        XCTAssertNotNil(module.buildActions(ticket: PresFixtures.issue("3")))
        XCTAssertNotNil(module.buildDetailSidebar(ticket: PresFixtures.issue("3")))
        var plain = PresFixtures.issue("9"); plain.providerEntity = nil
        XCTAssertNil(module.buildDetailSidebar(ticket: plain))

        // scopeTickets follows the account on screen
        ctx.nav.select(.account("gh-a"))
        var other = PresFixtures.pr("x"); other.accountId = "gh-b"
        let scoped = module.scopeTickets(location: ToolLocation(section: "github.pulls", scopeId: "acme/web"), tickets: store.tickets + [other])
        XCTAssertEqual(scoped.map(\.id).sorted(), ["1", "2", "3", "4"])

        var title: [String?] = []
        for await v in module.scopeTitle(account: PresFixtures.account, location: ToolLocation(section: "github.pulls", scopeId: "acme/web"))! { title.append(v) }
        XCTAssertEqual(title, ["acme/web"])
        XCTAssertNil(module.scopeTitle(account: PresFixtures.account, location: ToolLocation(section: "github.pulls")))

        var first: ToolMetrics?
        for await m in module.metrics(account: PresFixtures.account) { first = m; break }
        XCTAssertEqual(first?.primaryCount, 1)
        XCTAssertEqual(first?.secondaryCount, 2)
        XCTAssertEqual(first?.primaryLabel, "Pull Requests")
        XCTAssertEqual(first?.secondaryLabel, "Issues")
    }
}
