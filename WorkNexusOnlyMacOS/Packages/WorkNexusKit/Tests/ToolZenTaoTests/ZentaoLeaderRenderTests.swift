import AppKit
import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI
import XCTest
@testable import ToolZenTao

/// Renders the team leader's bar, filtered boards and the bulk bar off-screen (`/tmp/wn-zentao-render/leader-*.png`).
/// Asserts the pixels are not blank and the state the picture is meant to show.
@MainActor
final class ZentaoLeaderRenderTests: XCTestCase {
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
        try png.write(to: outDir.appendingPathComponent("leader-\(name).png"))
        XCTAssertGreaterThan(png.count, 2_000, "\(name) rendered blank")
    }

    private func day(_ offset: Int) -> String { AppDateFormatBridge.iso(Date().addingTimeInterval(Double(offset) * 86_400)) }

    private var members: [ProviderUser] {
        [ProviderUser(account: "thanh", displayName: "Thanh Pham"), ProviderUser(account: "cat", displayName: "Cat Le"),
         ProviderUser(account: "luci", displayName: "Luci Tran"), ProviderUser(account: "idle", displayName: "Minh Vo")]
    }

    private func task(_ key: String, _ status: String, who: String?, pri: Priority = .medium, due: Int? = nil, left: Double = 4,
                      updated: Int = 0) -> Ticket {
        var t = boardTask(key, providerStatus: status, status: status == "wait" ? .todo : (status == "done" ? .review : .inprogress),
                          assignee: who, updated: Date().addingTimeInterval(Double(-updated) * 86_400))
        t.title = ["Build the share sheet", "Fix the feed scrolling", "Wire the payment gateway", "Write the release notes",
                   "Review the onboarding copy", "Profile the cold start", "Migrate the settings store"][Int(key)! % 7]
        t.priority = pri
        t.providerEntity = .zentaoTask(ZenTaoTaskEntity(execution: "e1", estimate: 8, left: left, deadline: due.map(day)))
        return t
    }

    private var tasks: [Ticket] {
        [task("1", "doing", who: "thanh", pri: .urgent, due: -3), task("2", "doing", who: "thanh", due: 1),
         task("3", "wait", who: "thanh", due: 6), task("4", "doing", who: "cat", pri: .high, due: -1),
         task("5", "wait", who: "cat", due: 2), task("6", "pause", who: "luci", updated: 12),
         task("7", "wait", who: nil, pri: .high, due: 4, left: 0), task("8", "wait", who: nil), task("9", "doing", who: "luci", due: 0),
         task("10", "done", who: "thanh", due: -8)]
    }

    private func env() async -> BoardsEnv {
        let all = tasks
        let env = BoardsEnv(section: ZentaoSection.tasks, tickets: all, members: members)
        env.pages.script = ["wait": all.filter { $0.providerStatus == "wait" }, "doing": all.filter { $0.providerStatus == "doing" },
                            "pause": all.filter { $0.providerStatus == "pause" }, "done": all.filter { $0.providerStatus == "done" }]
        env.state.openExecution(env.execution("e1", "Sprint 12"))
        await env.wait { env.state.taskBoard.scoped.count == all.count }
        env.state.loadBoardMembers(bugs: false)
        await env.wait { env.state.boardMembers(bugs: false).count == 4 }
        return env
    }

    private func section(_ env: BoardsEnv) -> some View {
        ZentaoModule(env.deps, state: env.state).buildSection(account: env.store.accounts["zt1"]!, location: env.nav.location(for: "zt1"))
    }

    func testLeaderBarOnTheTaskBoard() async throws {
        let env = await env()
        try await render("tasks", section(env), size: CGSize(width: 1500, height: 640))
        try await render("tasks-dark", section(env), size: CGSize(width: 1500, height: 640), dark: true)
        let load = env.state.workload(bugs: false)
        XCTAssertEqual(load.map(\.login), ["thanh", "cat", "luci", "idle", ""])   // most overdue first, the idle member listed, nobody last
        XCTAssertEqual(load.first { $0.login == "thanh" }?.open, 2 + 1)            // the done one is not load
        XCTAssertEqual(env.state.quickCounts(bugs: false)[.overdue], 2)
    }

    func testFilteredBoardWithAPickedTicketShowsTheBulkBar() async throws {
        let env = await env()
        env.state.updateLeader(bugs: false) { $0.people = ["thanh"]; $0.quick = [.overdue, .dueSoon] }
        XCTAssertEqual(env.state.shownTickets(bugs: false).map(\.externalKey).sorted(), ["1", "2"])
        env.state.taskBoard.select(env.state.shownTickets(bugs: false).map(\.id))
        XCTAssertEqual(env.state.bulkTargets(bugs: false).count, 2)
        try await render("tasks-filtered-bulk", section(env), size: CGSize(width: 1500, height: 640))
        // A ticket a filter has since hidden is no longer a target.
        env.state.updateLeader(bugs: false) { $0.quick = [.overdue] }
        XCTAssertEqual(env.state.bulkTargets(bugs: false).map(\.externalKey), ["1"])
    }

    func testListWithDeadlineAndHours() async throws {
        let env = await env()
        env.nav.setViewMode("list", section: ZentaoSection.tasks, accountId: "zt1")
        try await render("tasks-list", section(env), size: CGSize(width: 1300, height: 560))
    }

    func testTeamBoardShowsTheTeamAndWhoCouldNotBeRead() async throws {
        let env = await env()
        var extra = task("11", "doing", who: "idle", due: 2)
        extra.providerEntity = .zentaoTask(ZenTaoTaskEntity(execution: "e7", estimate: 5, left: 5, executionName: "Sprint 7 · Payments", deadline: day(2)))
        _ = await env.store.upsertTickets([extra])
        env.pages.personWork = [
            "thanh": ZenTaoPersonWork(ids: tasks.filter { $0.assignee == "thanh" }.map(\.id), total: 4, truncated: false),
            "cat": ZenTaoPersonWork(ids: tasks.filter { $0.assignee == "cat" }.map(\.id), total: 2, truncated: false),
            "idle": ZenTaoPersonWork(ids: [extra.id], total: 1, truncated: false)]
        env.pages.personFailures["luci"] = .network("ZenTao did not show this person's work")
        let team = ZenTaoTeamGroup(id: "g", accountId: "zt1", name: "Mobile squad", members: members.map { ZenTaoTeamMember(login: $0.account, name: $0.displayName) })
        env.state.openTeam(team, bugs: false)
        await env.wait { env.state.taskTeam?.isLoading == false }
        XCTAssertEqual(env.state.taskTeam?.failed, ["luci"])
        try await render("team-board", section(env), size: CGSize(width: 1500, height: 640))
    }

    func testGroupDialogIsAsTallAsItsContentAndTheListScrolls() async throws {
        let env = await env()
        let account = env.store.accounts["zt1"]!
        let many = (1...40).map { ProviderUser(account: "user\($0)", displayName: "Person \($0)_VN_Flutter") }
        try await render("group-dialog-many", AppDialogFrameHost { ZentaoTeamGroupDialog(deps: env.deps, state: env.state, account: account, bugs: false,
                                                                                         editing: nil, people: many, onClose: {}) },
                         size: CGSize(width: 700, height: 800))
        try await render("group-dialog-few", AppDialogFrameHost { ZentaoTeamGroupDialog(deps: env.deps, state: env.state, account: account, bugs: false,
                                                                                        editing: nil, people: Array(many.prefix(3)), onClose: {}) },
                         size: CGSize(width: 700, height: 800))
    }

    func testPickingModeShowsCheckboxesOnTheBoardAndTheList() async throws {
        let env = await env()
        env.state.taskBoard.beginSelecting()
        let picked = env.state.shownTickets(bugs: false).filter { ["1", "4", "7"].contains($0.externalKey) }.map(\.id)
        env.state.taskBoard.select(picked)
        XCTAssertTrue(env.state.taskBoard.isSelecting)
        XCTAssertEqual(env.state.bulkTargets(bugs: false).count, 3)
        try await render("tasks-picking", section(env), size: CGSize(width: 1500, height: 640))
        env.nav.setViewMode("list", section: ZentaoSection.tasks, accountId: "zt1")
        try await render("tasks-picking-list", section(env), size: CGSize(width: 1300, height: 560))
        env.state.taskBoard.endSelecting()
        XCTAssertTrue(env.state.taskBoard.selectedIds.isEmpty)
    }

    func testBulkAssignDialogListsThePeopleWithTheirLoad() async throws {
        let env = await env()
        env.state.togglePinned("luci")
        // Task 7 has no hours left: the dialog asks for them.
        env.state.taskBoard.select(env.state.shownTickets(bugs: false).filter { ["1", "4", "7"].contains($0.externalKey) }.map(\.id))
        XCTAssertEqual(env.state.bulkTargets(bugs: false).filter { NeedsHoursLeft()($0) }.map(\.externalKey), ["7"])
        for dark in [false, true] {
            try await render("bulk-assign\(dark ? "-dark" : "")", AppDialogFrameHost {
                ZentaoBulkAssignDialog(deps: env.deps, state: env.state, bugs: false, model: ZentaoBulkModel(), onClose: {})
            }, size: CGSize(width: 760, height: 860), dark: dark)
        }
    }

    /// "New todo" as a chat message opens it: the name and the note filled in.
    func testNewTodoDialogFilledFromAChatMessage() async throws {
        let seed = ZentaoTodoPrompt.Seed(accountId: "zt", name: "Login fails on Safari after the last deploy",
                                         desc: "Login fails on Safari after the last deploy\n\nFrom chat: Release Team · An, 2026-11-17 10:32")
        for dark in [false, true] {
            try await render("todo-dialog\(dark ? "-dark" : "")", ZentaoTodoDialog(seed: seed, todos: SilentTodos(), onClose: {}),
                             size: CGSize(width: 620, height: 520), dark: dark)
        }
    }
}

private struct SilentTodos: ZenTaoTodos {
    func createTodo(accountId: String, todo: ZenTaoTodoDraft) async -> Outcome<Int?> { .success(nil) }
}

/// The dialog on a plain backdrop, top-aligned so its own height shows.
private struct AppDialogFrameHost<Content: View>: View {
    let content: () -> Content
    var body: some View { content().padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }
}
