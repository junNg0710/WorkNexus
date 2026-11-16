import AppKit
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI
import XCTest
@testable import ToolGitLab

/// Renders the GitLab board, lists, nav pane and MR detail off-screen so layout crashes show up in the test run and the
/// PNGs can be eyeballed (`/tmp/wn-git-render/gitlab-*.png`). Asserts only that something non-blank was drawn.
@MainActor
final class PresentationRenderTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/wn-git-render")

    private func render<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false, wait: Duration = .milliseconds(500)) async throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var settings = AppSettings(); if dark { settings.variant = .dark }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.environment(\.appTheme, theme).frame(width: size.width, height: size.height)
            .background(theme.colors.bg).environment(\.colorScheme, theme.colorScheme))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: wait)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: outDir.appendingPathComponent("gitlab-\(name).png"))
        XCTAssertGreaterThan(png.count, 2_000, "\(name) rendered blank")
    }

    private func context() -> (GitlabContext, GLPresMrService) {
        let store = GLPresStore()
        store.accounts = [GLPresFixtures.account]
        store.tickets = [
            GLPresFixtures.mr("101", title: "feat: add analytics dashboard", reviewers: ["Ana Lopez"]),
            GLPresFixtures.mr("102", title: "fix: crash when the token expires while syncing in the background", status: .inprogress, providerStatus: "draft", draft: true),
            GLPresFixtures.mr("103", title: "chore: bump dependencies", status: .done, providerStatus: "merged"),
            GLPresFixtures.mr("104", title: "refactor: split the sync coordinator", status: .done, providerStatus: "closed", mergeStatus: nil),
            GLPresFixtures.mr("105", title: "docs: update the README", labels: ["docs", "frontend"], updated: Date().addingTimeInterval(-5 * 3600)),
            GLPresFixtures.issue("7", title: "Crash on start"), GLPresFixtures.issue("8", title: "Dark mode contrast", status: .inprogress),
        ]
        let service = GLPresMrService()
        service.projects = [ProviderProject(id: "12", name: "icom / web / app", accountId: "gl-a"), ProviderProject(id: "13", name: "icom / web / api", accountId: "gl-a"),
                            ProviderProject(id: "14", name: "icom / server / storage", accountId: "gl-a"), ProviderProject(id: "15", name: "tools / cli", accountId: "gl-a"),
                            ProviderProject(id: "16", name: "playground", accountId: "gl-a")]
        service.users = [ProviderUser(account: "jdoe", displayName: "Jane Doe"), ProviderUser(account: "ana", displayName: "Ana Lopez")]
        service.labels = [ProviderLabelOption(name: "frontend", color: "#428BCA"), ProviderLabelOption(name: "bug", color: "#D9534F"), ProviderLabelOption(name: "docs")]
        service.milestones = [ProviderMilestoneOption(id: 1, title: "v1.2"), ProviderMilestoneOption(id: 2, title: "v1.3")]
        service.commits = [RepoCommit(sha: "a1b2c3d4e5f6", shortSha: "a1b2c3d", title: "Add dashboard shell", author: "ana", date: Date().addingTimeInterval(-7200))]
        service.files = [RepoFileChange(path: "lib/dashboard.dart", additions: 2, deletions: 1, status: "modified", diff: "@@ -1,2 +1,3 @@\n-old\n+new\n+more")]
        let (ctx, _, _, _) = GLPresFixtures.context(store: store, service: service)
        ctx.nav.select(.account("gl-a"))
        ctx.start()
        return (ctx, service)
    }

    func testMergeRequestBoard() async throws {
        let (ctx, _) = context()
        ctx.nav.setViewMode("board", section: GitlabSections.mrs, accountId: "gl-a")
        try await render("mr-board", GitlabItemsSection(ctx: ctx, account: GLPresFixtures.account, kind: .mergeRequest), size: CGSize(width: 1200, height: 620), wait: .milliseconds(900))
        try await render("mr-board-dark", GitlabItemsSection(ctx: ctx, account: GLPresFixtures.account, kind: .mergeRequest), size: CGSize(width: 1200, height: 620), dark: true, wait: .milliseconds(900))
    }

    func testListsAndIssueBoard() async throws {
        let (ctx, _) = context()
        try await render("mr-list", GitlabItemsSection(ctx: ctx, account: GLPresFixtures.account, kind: .mergeRequest), size: CGSize(width: 1000, height: 420), wait: .milliseconds(900))
        ctx.nav.setViewMode("merged", section: GitlabSections.mrs, accountId: "gl-a")
        try await render("mr-list-merged", GitlabItemsSection(ctx: ctx, account: GLPresFixtures.account, kind: .mergeRequest), size: CGSize(width: 1000, height: 300), wait: .milliseconds(900))
        try await render("issue-list", GitlabItemsSection(ctx: ctx, account: GLPresFixtures.account, kind: .issue), size: CGSize(width: 1000, height: 360), wait: .milliseconds(900))
        ctx.nav.setViewMode("board", section: GitlabSections.issues, accountId: "gl-a")
        try await render("issue-board", GitlabItemsSection(ctx: ctx, account: GLPresFixtures.account, kind: .issue), size: CGSize(width: 1000, height: 460), wait: .milliseconds(900))
        try await render("pipelines-placeholder", ComingSoonView(systemImage: "play", title: "Pipelines"), size: CGSize(width: 500, height: 300), wait: .milliseconds(50))
    }

    func testNavPane() async throws {
        let (ctx, service) = context()
        let module = GitlabModule(services: ctx.services, nav: ctx.nav, registry: ctx.registry, mrService: service)
        module.ctx.start()
        try await Task.sleep(for: .milliseconds(150))
        ctx.nav.setScope("13", accountId: "gl-a")
        module.ctx.togglePinnedProject("gl-a:15")
        let pane = module.buildNavPane(account: GLPresFixtures.account, location: ctx.nav.location(for: "gl-a"))
        try await render("nav-pane", pane.frame(width: 300), size: CGSize(width: 300, height: 560), wait: .milliseconds(900))
    }

    private func detailTicket(_ key: String, _ build: (inout Ticket, inout GitLabItemEntity) -> Void = { _, _ in }) -> (Ticket, GitLabItemEntity) {
        var t = GLPresFixtures.mr(key, reviewers: ["Ana Lopez"], approvedBy: ["Ana Lopez"], body: "Adds the analytics dashboard.\n\n- charts for **sync** latency\n- a table of recent failures\n\n```swift\nlet x = 1\n```")
        guard case .gitlabItem(var e)? = t.providerEntity else { fatalError() }
        build(&t, &e)
        t.providerEntity = .gitlabItem(e)
        return (t, e)
    }

    func testMergeRequestDetailStates() async throws {
        let comments = [Comment(id: "c1", ticketId: "201", authorName: "Ana Lopez", body: "Looks good, one nit on the chart colours.", createdAt: Date().addingTimeInterval(-3600))]
        let store = GLPresStore(); store.comments = comments
        let service = GLPresMrService(); service.users = [ProviderUser(account: "jdoe", displayName: "Jane Doe")]
        let (ctx, _, _, _) = GLPresFixtures.context(store: store, service: service)
        ctx.nav.select(.account("gl-a"))
        let open = detailTicket("201")
        try await render("mr-detail", GitlabMrDetail(ctx: ctx, ticket: open.0, entity: open.1, onClose: {}), size: CGSize(width: 1000, height: 820), wait: .milliseconds(900))
        try await render("mr-detail-dark", GitlabMrDetail(ctx: ctx, ticket: open.0, entity: open.1, onClose: {}), size: CGSize(width: 1000, height: 820), dark: true, wait: .milliseconds(900))
        try await render("mr-detail-narrow", GitlabMrDetail(ctx: ctx, ticket: open.0, entity: open.1, onClose: {}), size: CGSize(width: 640, height: 1000), wait: .milliseconds(900))
        let rebase = detailTicket("202") { _, e in e.mergeStatus = "need_rebase"; e.commitsBehind = 2 }
        try await render("mr-detail-rebase", GitlabMrDetail(ctx: ctx, ticket: rebase.0, entity: rebase.1, onClose: {}), size: CGSize(width: 1000, height: 640), wait: .milliseconds(600))
        let draft = detailTicket("203") { t, e in t.providerStatus = "draft"; e.draft = true }
        try await render("mr-detail-draft", GitlabMrDetail(ctx: ctx, ticket: draft.0, entity: draft.1, onClose: {}), size: CGSize(width: 1000, height: 640), wait: .milliseconds(600))
        let merged = detailTicket("204") { t, e in
            t.providerStatus = "merged"; t.status = .done
            e.mergedBy = "Ana Lopez"; e.mergedAt = Date().addingTimeInterval(-7200); e.mergeCommitSha = "0123456789abcdef"; e.squashCommitSha = "fedcba9876543210"; e.removeSourceBranch = true
        }
        try await render("mr-detail-merged", GitlabMrDetail(ctx: ctx, ticket: merged.0, entity: merged.1, onClose: {}), size: CGSize(width: 1000, height: 640), wait: .milliseconds(600))
        let closed = detailTicket("205") { t, e in t.providerStatus = "closed"; t.status = .done; e.closedBy = "Jane Doe"; e.closedAt = Date().addingTimeInterval(-600) }
        try await render("mr-detail-closed", GitlabMrDetail(ctx: ctx, ticket: closed.0, entity: closed.1, onClose: {}), size: CGSize(width: 1000, height: 560), wait: .milliseconds(600))
    }

    func testEditorsAndHeaderPieces() async throws {
        let (ctx, service) = context()
        let (t, e) = detailTicket("301")
        let loader: @Sendable (String) async -> Data? = { _ in nil }
        try await render("editor-labels", GitlabLabelsEditor(currentLabels: ["frontend"], loadOptions: { await service.listGitLabLabels(t) }, onSave: { _ in .success(()) }, onClose: {}).padding(16),
                         size: CGSize(width: 380, height: 420), wait: .milliseconds(500))
        try await render("editor-milestone", GitlabMilestoneEditor(currentMilestoneId: 1, loadOptions: { await service.listGitLabMilestones(t) }, onSave: { _ in .success(()) }, onClose: {}).padding(16),
                         size: CGSize(width: 380, height: 380), wait: .milliseconds(500))
        try await render("editor-time", GitlabTimeTrackingEditor(currentEstimate: "2h", currentSpent: "30m", onSave: { _, _, _, _ in .success(()) }, onClose: {}).padding(16),
                         size: CGSize(width: 380, height: 360), wait: .milliseconds(300))
        try await render("editor-reviewers", GitlabUserPickerEditor(currentUsers: ["Ana Lopez"], multiple: true, loadUsers: { await service.listUsers(t) }, onSave: { _ in .success(()) }, onClose: {}, avatarLoader: loader).padding(16),
                         size: CGSize(width: 380, height: 420), wait: .milliseconds(500))
        try await render("sidebar", GitlabMrSidebar(ctx: ctx, ticket: t, entity: e).padding(16).frame(width: 320), size: CGSize(width: 320, height: 640), wait: .milliseconds(300))
        let issue = GLPresFixtures.issue("7")
        try await render("issue-actions", GitlabActions(ctx: ctx, ticket: issue).padding(16), size: CGSize(width: 600, height: 80), wait: .milliseconds(200))
        try await render("mr-actions", GitlabActions(ctx: ctx, ticket: t).padding(16), size: CGSize(width: 800, height: 100), wait: .milliseconds(200))
        try await render("detail-sections", GitlabDetailSections(ctx: ctx, ticket: t, entity: e).padding(16).frame(width: 360), size: CGSize(width: 360, height: 400), wait: .milliseconds(200))
        try await render("assign-dialog", GitlabAssignDialog(ctx: ctx, ticket: t, multiple: false) {}.padding(24), size: CGSize(width: 560, height: 640), wait: .milliseconds(600))
        try await render("branch-ref", GitlabBranchRef(branch: "feature/dashboard").padding(16), size: CGSize(width: 260, height: 60), wait: .milliseconds(100))
    }
}
