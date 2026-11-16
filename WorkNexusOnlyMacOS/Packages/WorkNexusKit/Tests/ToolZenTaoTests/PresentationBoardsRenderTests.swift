import AppKit
import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI
import XCTest
@testable import ToolZenTao

/// Renders the ZenTao boards, lists, section chrome, nav pane and docs section through `ZentaoModule` off-screen
/// (`/tmp/wn-zentao-render/boards-*.png`). Asserts only that something non-blank was drawn.
@MainActor
final class PresentationBoardsRenderTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/wn-zentao-render")

    private func render<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false) async throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var settings = AppSettings(); if dark { settings.variant = .dark }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.environment(\.appTheme, theme).frame(width: size.width, height: size.height)
            .background(theme.colors.bg).environment(\.colorScheme, theme.colorScheme))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(700))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: outDir.appendingPathComponent("boards-\(name).png"))
        XCTAssertGreaterThan(png.count, 2_000, "\(name) rendered blank")
    }

    private func module(_ env: BoardsEnv) -> ZentaoModule { ZentaoModule(env.deps, state: env.state) }

    private var bugs: [Ticket] {
        let now = Date()
        return [boardBug("101", status: .inbox, assignee: "Thanh", severity: 1, updated: now.addingTimeInterval(-300), priority: .urgent),
                boardBug("102", assignee: "Cat", severity: 2, updated: now.addingTimeInterval(-3 * 3600)),
                boardBug("103", providerStatus: "resolved", resolution: "fixed", assignee: "Luci", updated: now.addingTimeInterval(-2 * 86_400)),
                boardBug("104", providerStatus: "resolved", resolution: "bydesign", severity: 3),
                boardBug("105", providerStatus: "closed")]
    }

    private var tasks: [Ticket] {
        let soon = AppDateFormatBridge.iso(Date().addingTimeInterval(86_400)), late = AppDateFormatBridge.iso(Date().addingTimeInterval(-86_400 * 12))
        return [boardTask("201", deadline: soon, assignee: "Thanh"), boardTask("202", providerStatus: "doing", status: .inprogress, deadline: late),
                boardTask("203", providerStatus: "pause", status: .blocked), boardTask("204", providerStatus: "done", status: .review),
                boardTask("205", providerStatus: "closed", status: .done)]
    }

    private func bugEnv() async -> BoardsEnv {
        let env = BoardsEnv(section: ZentaoSection.bugs, tickets: bugs)
        env.pages.products = [env.product("p1", "VN_Socialfi"), env.product("p2", "VN_Chat")]
        env.pages.script = ["unconfirmed": [bugs[0]], "unresolved": [bugs[1]], "toclosed": Array(bugs[2...3]), "all": [bugs[4]]]
        env.state.loadProducts("zt1")
        await env.wait { env.state.products["zt1"]?.value != nil }
        env.state.openProduct(env.product("p1", "VN_Socialfi"))
        await env.wait { env.state.bugBoard.scoped.count == 4 }
        return env
    }

    private func taskEnv() async -> BoardsEnv {
        let env = BoardsEnv(section: ZentaoSection.tasks, tickets: tasks)
        env.pages.script = ["wait": [tasks[0]], "doing": [tasks[1]], "pause": [tasks[2]], "done": [tasks[3]], "closed": [tasks[4]]]
        env.state.openExecution(env.execution("e1", "Sprint 12"))
        await env.wait { env.state.taskBoard.scoped.count == 5 }
        return env
    }

    func testBugsSectionBoardAndList() async throws {
        let env = await bugEnv()
        let m = module(env)
        let location = env.nav.location(for: "zt1")
        let account = env.store.accounts["zt1"]!
        try await render("bugs-board", m.buildSection(account: account, location: location), size: CGSize(width: 1500, height: 640))
        try await render("bugs-board-dark", m.buildSection(account: account, location: location), size: CGSize(width: 1500, height: 640), dark: true)
        env.nav.setViewMode("list", section: ZentaoSection.bugs, accountId: "zt1")
        try await render("bugs-list", m.buildSection(account: account, location: env.nav.location(for: "zt1")), size: CGSize(width: 1200, height: 480))
    }

    func testTasksSectionBoardAndList() async throws {
        let env = await taskEnv()
        let m = module(env)
        let account = env.store.accounts["zt1"]!
        try await render("tasks-board", m.buildSection(account: account, location: env.nav.location(for: "zt1")), size: CGSize(width: 1900, height: 560))
        env.nav.setViewMode("list", section: ZentaoSection.tasks, accountId: "zt1")
        try await render("tasks-list", m.buildSection(account: account, location: env.nav.location(for: "zt1")), size: CGSize(width: 1200, height: 460))
    }

    func testTasksSectionWithoutAnExecutionAsksToPickOne() async throws {
        let env = BoardsEnv(section: ZentaoSection.tasks)
        try await render("tasks-pick", module(env).buildSection(account: env.store.accounts["zt1"]!, location: env.nav.location(for: "zt1")),
                         size: CGSize(width: 900, height: 360))
    }

    func testNavPanesThroughTheModule() async throws {
        let env = await bugEnv()
        let m = module(env)
        let account = env.store.accounts["zt1"]!
        try await render("nav-bugs", m.buildNavPane(account: account, location: env.nav.location(for: "zt1")).frame(width: 300), size: CGSize(width: 300, height: 600))
        let tasks = await taskEnv()
        try await render("nav-tasks", module(tasks).buildNavPane(account: account, location: tasks.nav.location(for: "zt1")).frame(width: 300), size: CGSize(width: 300, height: 600))
        tasks.nav.setSection(ZentaoSection.docs, accountId: "zt1")
        try await render("nav-docs", module(tasks).buildNavPane(account: account, location: tasks.nav.location(for: "zt1")).frame(width: 300), size: CGSize(width: 300, height: 400))
        try await render("docs-empty", module(tasks).buildSection(account: account, location: tasks.nav.location(for: "zt1")), size: CGSize(width: 700, height: 360))
    }

    func testModuleContract() async throws {
        let env = await bugEnv()
        let m = module(env)
        XCTAssertEqual(m.providerType, .zentao)
        XCTAssertEqual(m.defaultSection, ZentaoSection.tasks)
        XCTAssertTrue(m.sectionsOnRail)
        XCTAssertEqual(m.sections.map(\.id), [ZentaoSection.tasks, ZentaoSection.bugs, ZentaoSection.docs])
        XCTAssertEqual(m.sections.first?.viewModes.map(\.id), ["board", "list"])
        XCTAssertEqual(m.sections.last?.viewModes.count, 0)
        XCTAssertTrue(m.paneCollapsible(location: ToolLocation(section: ZentaoSection.docs)))
        XCTAssertTrue(m.paneCollapsible(location: ToolLocation(section: ZentaoSection.bugs)))   // every pane folds
        let account = env.store.accounts["zt1"]!
        XCTAssertEqual(m.webURL(account: account, location: ToolLocation(section: ZentaoSection.docs))?.absoluteString, "https://zentao.example.com/doc-index.html")
        XCTAssertEqual(m.webURL(account: account, location: ToolLocation(section: ZentaoSection.bugs, scopeId: "4"))?.absoluteString, "https://zentao.example.com/product-browse-4.html")
        XCTAssertEqual(m.webURL(account: account, location: ToolLocation(section: ZentaoSection.tasks, scopeId: "9"))?.absoluteString, "https://zentao.example.com/project-task-9.html")
        XCTAssertEqual(m.webURL(account: account, location: ToolLocation(section: ZentaoSection.bugs))?.absoluteString, "https://zentao.example.com/product.html")
        XCTAssertEqual(m.webURL(account: account, location: ToolLocation(section: ZentaoSection.tasks))?.absoluteString, "https://zentao.example.com/project.html")
        XCTAssertNil(m.webURL(account: Account(id: "x", workspaceId: "w", providerType: .zentao, handle: "h"), location: ToolLocation(section: ZentaoSection.tasks)))
        XCTAssertEqual(m.scopeTickets(location: ToolLocation(section: ZentaoSection.docs), tickets: bugs).count, bugs.count)
        XCTAssertNil(m.buildDetail(ticket: bugs[0], onClose: {}), "ZenTao uses the standard tabbed panel")
        XCTAssertNotNil(m.buildActions(ticket: bugs[0]))
        XCTAssertNotNil(m.buildStatusStrip(ticket: bugs[0]))
        XCTAssertNil(m.buildDetailEffort(ticket: bugs[0]))
        XCTAssertEqual(m.roleLabel, "Project management")
        var it = m.metrics(account: account).makeAsyncIterator()
        let metrics = await it.next() ?? nil
        XCTAssertNotNil(metrics)
        var titles = m.scopeTitle(account: account, location: ToolLocation(section: ZentaoSection.bugs, scopeId: "p1"))!.makeAsyncIterator()
        let title = await titles.next() ?? nil
        XCTAssertEqual(title, "VN_Socialfi")
        XCTAssertNil(m.scopeTitle(account: account, location: ToolLocation(section: ZentaoSection.docs)))
    }
}
