import AppKit
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI
import XCTest
@testable import ToolGitHub

/// Renders the GitHub board, list, nav pane and PR detail off-screen so layout crashes show up in the test run and the
/// PNGs can be eyeballed (`/tmp/wn-git-render/github-*.png`). Asserts only that something non-blank was drawn.
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
        try png.write(to: outDir.appendingPathComponent("github-\(name).png"))
        XCTAssertGreaterThan(png.count, 2_000, "\(name) rendered blank")
    }

    private func context() -> (GithubContext, PresPrService) {
        let store = PresStore()
        store.accounts = [PresFixtures.account]
        store.tickets = [
            PresFixtures.pr("101", title: "feat: add analytics dashboard", reviewerLogins: ["octocat"]),
            PresFixtures.pr("102", title: "fix: crash when the token expires while syncing in the background", status: .inprogress, providerStatus: "draft", draft: true),
            PresFixtures.pr("103", title: "chore: bump dependencies", status: .done, providerStatus: "merged", merged: true),
            PresFixtures.pr("104", title: "refactor: split the sync coordinator", status: .done, providerStatus: "closed", mergeable: nil),
            PresFixtures.pr("105", title: "docs: update the README", labels: ["docs", "good first issue"], updated: Date().addingTimeInterval(-5 * 3600)),
            PresFixtures.issue("7", title: "Crash on start"), PresFixtures.issue("8", title: "Dark mode contrast", status: .inprogress),
        ]
        let service = PresPrService()
        service.repos = [ProviderProject(id: "acme/web", name: "acme/web", accountId: "gh-a"), ProviderProject(id: "acme/api", name: "acme/api", accountId: "gh-a"),
                         ProviderProject(id: "octo/tools", name: "octo/tools", accountId: "gh-a")]
        service.users = [ProviderUser(account: "octocat", displayName: "Octo Cat"), ProviderUser(account: "ana", displayName: "Ana Lopez")]
        service.commits = [RepoCommit(sha: "a1b2c3d4e5f6", shortSha: "a1b2c3d", title: "Add dashboard shell", author: "octocat", date: Date().addingTimeInterval(-7200))]
        service.files = [RepoFileChange(path: "lib/dashboard.dart", additions: 2, deletions: 1, status: "modified", diff: "@@ -1,2 +1,3 @@\n-old\n+new\n+more")]
        let (ctx, _, _, _) = PresFixtures.context(store: store, service: service)
        ctx.nav.select(.account("gh-a"))
        ctx.start()
        return (ctx, service)
    }

    func testPullRequestBoard() async throws {
        let (ctx, _) = context()
        ctx.nav.setViewMode("board", section: GithubSections.pulls, accountId: "gh-a")
        try await render("pr-board", GithubItemsSection(ctx: ctx, account: PresFixtures.account, kind: .pullRequest), size: CGSize(width: 1200, height: 620), wait: .milliseconds(900))
        try await render("pr-board-dark", GithubItemsSection(ctx: ctx, account: PresFixtures.account, kind: .pullRequest), size: CGSize(width: 1200, height: 620), dark: true, wait: .milliseconds(900))
    }

    func testListsAndIssueBoard() async throws {
        let (ctx, _) = context()
        try await render("pr-list", GithubItemsSection(ctx: ctx, account: PresFixtures.account, kind: .pullRequest), size: CGSize(width: 1000, height: 420), wait: .milliseconds(900))
        ctx.nav.setViewMode("merged", section: GithubSections.pulls, accountId: "gh-a")
        try await render("pr-list-merged", GithubItemsSection(ctx: ctx, account: PresFixtures.account, kind: .pullRequest), size: CGSize(width: 1000, height: 300), wait: .milliseconds(900))
        try await render("issue-list", GithubItemsSection(ctx: ctx, account: PresFixtures.account, kind: .issue), size: CGSize(width: 1000, height: 360), wait: .milliseconds(900))
        ctx.nav.setViewMode("board", section: GithubSections.issues, accountId: "gh-a")
        try await render("issue-board", GithubItemsSection(ctx: ctx, account: PresFixtures.account, kind: .issue), size: CGSize(width: 1000, height: 460), wait: .milliseconds(900))
        try await render("actions-placeholder", ComingSoonView(systemImage: "play", title: "Actions"), size: CGSize(width: 500, height: 300), wait: .milliseconds(50))
    }

    func testNavPane() async throws {
        let (ctx, service) = context()
        let module = GithubModule(services: ctx.services, nav: ctx.nav, registry: ctx.registry, prService: service)
        ctx.nav.setScope("acme/api", accountId: "gh-a")
        module.ctx.start()
        module.ctx.togglePinnedProject("gh-a:octo/tools")
        let pane = module.buildNavPane(account: PresFixtures.account, location: ctx.nav.location(for: "gh-a"))
        try await render("nav-pane", pane.frame(width: 300), size: CGSize(width: 300, height: 520), wait: .milliseconds(900))
    }

    func testPullRequestDetail() async throws {
        let (ctx, _) = context()
        let behind = PresFixtures.pr("201", mergeable: "behind", labels: ["frontend", "needs-review"])
        let body = "Adds the analytics dashboard.\n\n- charts for **sync** latency\n- a table of recent failures\n\n```swift\nlet x = 1\n```"
        var t = behind; t.body = body
        guard case .githubItem(let e)? = t.providerEntity else { return XCTFail() }
        var e2 = e; e2.reviewers = ["Ana Lopez"]
        let comments = [Comment(id: "c1", ticketId: "201", authorName: "Ana Lopez", body: "Looks good, one nit on the chart colours.", createdAt: Date().addingTimeInterval(-3600))]
        let store = PresStore(); store.comments = comments
        let (c2, _, _, svc) = PresFixtures.context(store: store)
        svc.users = [ProviderUser(account: "octocat", displayName: "Octo Cat")]
        c2.nav.select(.account("gh-a"))
        try await render("pr-detail", GithubPrDetail(ctx: c2, ticket: t, entity: e2, onClose: {}), size: CGSize(width: 1000, height: 780), wait: .milliseconds(900))
        try await render("pr-detail-dark", GithubPrDetail(ctx: c2, ticket: t, entity: e2, onClose: {}), size: CGSize(width: 1000, height: 780), dark: true, wait: .milliseconds(900))
        // narrow: stacked overview
        try await render("pr-detail-narrow", GithubPrDetail(ctx: c2, ticket: t, entity: e2, onClose: {}), size: CGSize(width: 640, height: 900), wait: .milliseconds(900))
        // closed + merged states
        var closed = t; closed.providerStatus = "closed"; closed.status = .done
        try await render("pr-detail-closed", GithubPrDetail(ctx: c2, ticket: closed, entity: e2, onClose: {}), size: CGSize(width: 1000, height: 600), wait: .milliseconds(600))
        _ = ctx
    }

    func testIssueDetailPieces() async throws {
        let (ctx, _) = context()
        let issue = PresFixtures.issue("7")
        try await render("issue-actions", GithubActions(ctx: ctx, ticket: issue).padding(16), size: CGSize(width: 600, height: 80), wait: .milliseconds(200))
        let pr = PresFixtures.pr("9", mergeable: "behind")
        try await render("pr-actions", GithubActions(ctx: ctx, ticket: pr).padding(16), size: CGSize(width: 700, height: 100), wait: .milliseconds(200))
        guard case .githubItem(let e)? = pr.providerEntity else { return XCTFail() }
        try await render("detail-sections", GithubDetailSections(ctx: ctx, ticket: pr, entity: e).padding(16).frame(width: 360), size: CGSize(width: 360, height: 360), wait: .milliseconds(200))
        try await render("assign-dialog", GithubAssignDialog(ctx: ctx, ticket: pr, multiple: false) {}.padding(24), size: CGSize(width: 560, height: 640), wait: .milliseconds(600))
        try await render("reviewers-dialog", GithubAssignDialog(ctx: ctx, ticket: pr, multiple: true) {}.padding(24), size: CGSize(width: 560, height: 560), wait: .milliseconds(600))
    }
}
