import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI
import XCTest
@testable import ToolZenTao

/// Ports of the logic-heavy ZenTao detail presentation tests: test/widget/{zentao_ticket_actions,parent_task_link,
/// bug_status_strip,task_bugs_card}_test.dart, test/unit/zentao_file_preview_test.dart.
@MainActor
final class PresentationDetailLogicTests: XCTestCase {
    private func labels(_ items: [ZentaoActionsModel.Item]) -> [String] { items.map { ZentaoActionsModel.look($0).label } }

    // MARK: Action bar (zentao_ticket_actions_test)

    func testATaskInProgressOffersWhatZenTaoAllows() {
        let m = ZentaoActionsModel(detailTicket("Task", "doing", entity: .zentaoTask(ZenTaoTaskEntity(execution: "31"))))
        // ZenTao's own toolbar: Child Task, Assign, then the status actions it allows now; finishing moves it on.
        // Every action is a button: nothing waits in a "more" menu.
        XCTAssertEqual(labels(m.buttons), ["Add subtask", "Assign", "Pause", "Finish", "Cancel task", "Report bug"])
        XCTAssertEqual(m.primary.map { ZentaoActionsModel.look($0).label }, "Finish")
        XCTAssertTrue(m.canAssign)
        XCTAssertEqual(labels(m.tools), ["Edit", "Clone task", "Delete"])
    }

    func testATaskNotStartedOffersStartFinishAndCancel() {
        let m = ZentaoActionsModel(detailTicket("Task", "wait", entity: .zentaoTask(ZenTaoTaskEntity(execution: "31"))))
        XCTAssertEqual(labels(m.buttons), ["Add subtask", "Assign", "Start", "Finish", "Cancel task", "Report bug"])
        XCTAssertEqual(m.primary, .task(.start))
    }

    func testAnUnconfirmedBugIsConfirmedFirst() {
        let m = ZentaoActionsModel(detailTicket("Bug", "active", status: .inbox))
        XCTAssertEqual(labels(m.buttons), ["Confirm", "Assign", "Resolve", "Convert to Task"])
        XCTAssertEqual(m.primary, .bug(.confirm))
        XCTAssertEqual(labels(m.tools), ["Edit", "Copy", "Delete"])
    }

    func testAClosedBugCanOnlyBeReopened() {
        let m = ZentaoActionsModel(detailTicket("Bug", "closed"))
        XCTAssertEqual(labels(m.buttons), ["Activate"])
        XCTAssertEqual(m.primary, .bug(.activate))
        XCTAssertFalse(m.canAssign)
        XCTAssertEqual(labels(m.tools), ["Edit", "Copy", "Delete"], "it can still be edited, copied and deleted")
    }

    func testAStoryOffersAssignOnly() {
        let m = ZentaoActionsModel(detailTicket("Story", "active"))
        XCTAssertEqual(m.buttons, [.assign]); XCTAssertNil(m.primary); XCTAssertTrue(m.tools.isEmpty)
    }

    func testATaskStartsASubtaskOfItselfInTheEditor() {
        let t = detailTicket("Task", "doing", entity: .zentaoTask(ZenTaoTaskEntity(execution: "31")))
        XCTAssertEqual(zentaoEditorRoute(for: .subtask, ticket: t), .newTask(accountId: "zt", executionId: "31", parentId: "12"))
        XCTAssertEqual(zentaoEditorRoute(for: .copyTask, ticket: t), .newTask(accountId: "zt", executionId: "31", copyOf: "12"))
        XCTAssertEqual(zentaoEditorRoute(for: .bugFromTask, ticket: t), .newBug(accountId: "zt", executionId: "31", taskId: "12"))
    }

    func testABugIsCopiedInItsProductAndBecomesATaskInItsExecution() {
        let t = detailTicket("Bug", "active", entity: .zentaoBug(ZenTaoBugEntity(product: "4", execution: "31")))
        XCTAssertEqual(zentaoEditorRoute(for: .copyBug, ticket: t), .newBug(accountId: "zt", productId: "4", copyOf: "12"))
        XCTAssertEqual(zentaoEditorRoute(for: .taskFromBug, ticket: t), .newTask(accountId: "zt", executionId: "31", fromBug: "12"))
        // A bug outside any execution: the editor opens on the one ZenTao has current, to be picked there.
        let loose = detailTicket("Bug", "active", entity: .zentaoBug(ZenTaoBugEntity(product: "4")))
        XCTAssertEqual(zentaoEditorRoute(for: .taskFromBug, ticket: loose), .newTask(accountId: "zt", executionId: "0", fromBug: "12"))
    }

    // MARK: Deleting

    func testDeletingForgetsTheTicketHereOnlyOnceZenTaoDeletedIt() async {
        final class Tickets: TicketRepository, @unchecked Sendable {
            var deleted: [String] = []
            func watchTickets() -> AsyncStream<[Ticket]> { AsyncStream { $0.finish() } }
            func ticket(id: String) async -> Outcome<Ticket?> { .success(nil) }
            func upsertTickets(_ tickets: [Ticket]) async -> Outcome<Void> { .success(()) }
            func moveTicket(id: String, to status: UnifiedStatus) async -> Outcome<Void> { .success(()) }
            func deleteTicket(id: String) async -> Outcome<Void> { deleted.append(id); return .success(()) }
        }
        let workflow = DetailFakeWorkflow(), tickets = Tickets()
        let bug = detailTicket("Bug", "active")
        let delete = DeleteZenTaoTicket(workflow: workflow, tickets: tickets)

        workflow.failure = .validation("no permission")
        let refused = await delete(bug)
        XCTAssertEqual(refused.failure, .validation("no permission"))
        XCTAssertTrue(tickets.deleted.isEmpty, "a bug ZenTao kept stays on the boards")

        workflow.failure = nil
        let done = await delete(bug)
        XCTAssertNotNil(done.value)
        XCTAssertEqual(workflow.deleted, [bug.id, bug.id])
        XCTAssertEqual(tickets.deleted, [bug.id])
    }

    // MARK: Task action form (zentao_task_action_dialog)

    func testFinishingAsksForTheHoursWorkedThenSendsThem() {
        let t = detailTicket("Task", "doing", entity: .zentaoTask(ZenTaoTaskEntity(consumed: 0)))
        var form = ZentaoTaskActionForm(ticket: t, action: .finish)
        XCTAssertEqual(form.problem, .spentRequired)
        form.spent = "2,5"
        XCTAssertNil(form.problem)
        XCTAssertEqual(form.input(comment: nil).spent, 2.5)
    }

    func testFinishingAsksWhatTheFinishFormDoes() {
        let began = Date(timeIntervalSince1970: 1_760_000_000)
        let t = detailTicket("Task", "doing", entity: .zentaoTask(ZenTaoTaskEntity(consumed: 16, realStarted: began, openedByHandle: "evan")))
        var form = ZentaoTaskActionForm(ticket: t, action: .finish, now: began.addingTimeInterval(3600))
        form.spent = "2"
        XCTAssertEqual(form.hoursHint, "16 h logged so far · 18 h in total")
        // A begin already recorded is shown, not changed; a finished task goes back to its creator by default.
        XCTAssertFalse(form.beginEditable)
        let input = form.input(comment: "done")
        XCTAssertEqual(input.assignee, "evan"); XCTAssertEqual(input.began, began)
        XCTAssertEqual(input.ended, began.addingTimeInterval(3600)); XCTAssertEqual(input.comment, "done")
    }

    func testStartingAsksWhenWorkReallyBeganAndKeepsTheHolder() {
        var t = detailTicket("Task", "wait", status: .todo, entity: .zentaoTask(ZenTaoTaskEntity(left: 4)))
        t.assignee = "cat"
        let form = ZentaoTaskActionForm(ticket: t, action: .start)
        XCTAssertTrue(form.action.asksBegin); XCTAssertFalse(form.action.asksEnd); XCTAssertFalse(form.action.asksFiles)
        XCTAssertEqual(form.assignee, "cat"); XCTAssertEqual(form.left, "4")
        XCTAssertNotNil(form.input(comment: nil).began); XCTAssertNil(form.input(comment: nil).ended)
    }

    func testTheEndNeverDefaultsBeforeTheBegin() {
        let future = Date().addingTimeInterval(86_400)
        let t = detailTicket("Task", "doing", entity: .zentaoTask(ZenTaoTaskEntity(consumed: 1, realStarted: future)))
        let form = ZentaoTaskActionForm(ticket: t, action: .finish)
        XCTAssertGreaterThanOrEqual(form.ended, form.began)
    }

    func testHoursParsingAndText() {
        XCTAssertEqual(zentaoParseHours(""), 0); XCTAssertEqual(zentaoParseHours(" 1,5 "), 1.5)
        XCTAssertTrue(zentaoParseHours("abc").isNaN)
        XCTAssertEqual(zentaoHoursText(2.5), "2.5"); XCTAssertEqual(zentaoHoursText(16), "16"); XCTAssertEqual(zentaoHoursText(0.126), "0.13")
        var form = ZentaoTaskActionForm(ticket: detailTicket("Task", "doing", entity: .zentaoTask(ZenTaoTaskEntity(consumed: 1))), action: .pause)
        form.spent = "x"
        XCTAssertNil(form.problem, "pause asks no hours")
        var restart = ZentaoTaskActionForm(ticket: detailTicket("Task", "pause", entity: .zentaoTask(ZenTaoTaskEntity())), action: .restart)
        restart.spent = "x"
        XCTAssertEqual(restart.problem, .invalidHours)
    }

    // MARK: Running an action

    func testAnActionDimsTheCardThenToastsItsOutcome() async {
        let env = DetailEnv()
        let toasts = AppToastController()
        let t = detailTicket("Task", "doing")
        let ok = await ZentaoActionRunner.run(state: env.state, ticket: t, toasts: toasts, label: "Finish") {
            XCTAssertTrue(env.state.taskBoard.pendingTicketIds.contains(t.id))
            return await env.workflow.runTaskAction(t, .finish, ZenTaoTaskActionInput(spent: 1))
        }
        XCTAssertTrue(ok)
        XCTAssertTrue(env.state.taskBoard.pendingTicketIds.isEmpty)
        XCTAssertEqual(toasts.toasts.first?.message, "Finish #12: done"); XCTAssertEqual(env.workflow.taskCalls.first?.1, .finish)
        env.workflow.failure = .network("down")
        let bad = await ZentaoActionRunner.run(state: env.state, ticket: t, toasts: toasts, label: "Finish") {
            await env.workflow.runTaskAction(t, .finish, ZenTaoTaskActionInput())
        }
        XCTAssertFalse(bad)
        XCTAssertEqual(toasts.toasts.first?.kind, .error); XCTAssertEqual(toasts.toasts.first?.message, "Failed: down")
    }

    func testAssigningGoesThroughTheAdapterThenRefreshes() async {
        let env = DetailEnv()
        let t = detailTicket("Task", "doing")
        let r = await ZentaoAssignAction.run(deps: env.deps, ticket: t, assignee: "cat", comment: "<p>hi</p>", left: 3)
        XCTAssertNotNil(r.value)
        XCTAssertEqual(env.adapter.assigned.first?.assignee, "cat"); XCTAssertEqual(env.adapter.assigned.first?.left, 3)
        XCTAssertEqual(env.sync.refreshed, [t.id])
    }

    func testAssigneesComeFromTheTeamElseTheAccountsUsers() async {
        let team = ProviderUser(account: "cat", displayName: "Cat")
        let withTeam = DetailEnv(members: [team])
        let bug = detailTicket("Bug", "active", entity: .zentaoBug(ZenTaoBugEntity(product: "4")))
        let a = await ZentaoAssignees.load(withTeam.deps, bug)
        XCTAssertEqual(a.value?.map(\.account), ["cat"])
        let noTeam = DetailEnv()
        noTeam.adapter.users = [ProviderUser(account: "ann", displayName: "Ann")]
        let b = await ZentaoAssignees.load(noTeam.deps, bug)
        XCTAssertEqual(b.value?.map(\.account), ["ann"])
    }

    // MARK: Linked tickets (parent_task_link_test)

    func testASyncedParentOpensWithoutFetching() async {
        let env = DetailEnv()
        let parent = detailTicket("Task", "doing", key: "12160", title: "Chat feature")
        env.store.tickets[parent.id] = parent
        let child = detailTicket("Task", "wait", key: "12167", url: "https://zentao.example.com/zentao/task-view-12167.html")
        let r = await env.deps.openLinked(from: child, type: "task", id: "12160")
        XCTAssertNotNil(r.value)
        XCTAssertEqual(env.nav.openTicketId, zenTaoTicketId(accountId: "zt", type: "task", id: "12160"))
        XCTAssertTrue(env.service.fetched.isEmpty)
    }

    func testAnUnsyncedParentIsFetchedFromZenTaoThenOpened() async {
        let env = DetailEnv()
        let child = detailTicket("Task", "wait", key: "12167", url: "https://zentao.example.com/zentao/task-view-12167.html")
        let r = await env.deps.openLinked(from: child, type: "task", id: "12160")
        XCTAssertNotNil(r.value)
        XCTAssertEqual(env.service.fetched.first?.host, "zentao.example.com"); XCTAssertEqual(env.service.fetched.first?.type, "task")
        XCTAssertEqual(env.nav.openTicketId, zenTaoTicketId(accountId: "zt", type: "task", id: "12160"))
    }

    // MARK: Related bugs (task_bugs_card_test)

    func testTheTaskBugsCardReadsStoredBugsAndSyncsTheExecution() async throws {
        let env = DetailEnv()
        let task = detailTicket("Task", "doing", key: "5", entity: .zentaoTask(ZenTaoTaskEntity(execution: "31")))
        let mine = detailTicket("Bug", "active", key: "9", entity: .zentaoBug(ZenTaoBugEntity(task: "5")))
        let other = detailTicket("Bug", "active", key: "10", entity: .zentaoBug(ZenTaoBugEntity(task: "6")))
        env.store.tickets[mine.id] = mine; env.store.tickets[other.id] = other
        let model = ZentaoTaskBugsModel()
        model.start(env.deps, ticket: task)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.bugs.map(\.externalKey), ["9"])
        XCTAssertEqual(env.service.bugSyncs.first?.1, "31"); XCTAssertEqual(env.service.bugSyncs.first?.2, "5")
        XCTAssertFalse(model.failed)
        env.service.bugSyncFailure = .network("x")
        model.retry(env.deps, ticket: task)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(model.failed); model.stop()
    }

    // MARK: Bug status strip, sidebar rows, previews

    func testAResolvedBugFoldsItsResolutionIntoTheStatusChip() {
        let bug = ZenTaoBugEntity(confirmed: 1, resolution: "fixed")
        XCTAssertEqual(ZentaoBugStatusStrip.label(ticket: detailTicket("Bug", "resolved", status: .review), bug: bug), "Resolved · Fixed")
        XCTAssertEqual(ZentaoBugStatusStrip.label(ticket: detailTicket("Bug", "active", status: .todo), bug: ZenTaoBugEntity(activatedCount: 2)), "Active")
        XCTAssertNil(ZentaoBugStatusStrip.label(ticket: detailTicket("Bug", ""), bug: bug))
    }

    func testTheBugSidebarGroupsFilledAndEmptyFields() {
        let bug = ZenTaoBugEntity(branch: "0", module: "7", productName: "Live", bugType: "codeerror", confirmed: 0, severity: 2, activatedCount: 1,
                                  openedBy: "Ryan", assignedTo: "Cat", closedBy: "")
        let rows = ZentaoBugSectionRows(bug: bug, ticket: detailTicket("Bug", "active"), dateFormat: "iso")
        let filled = Dictionary(rows.filled.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(filled["Severity"], "S2 · Major"); XCTAssertEqual(filled["Confirmation"], "Not confirmed")
        XCTAssertEqual(filled["Reopened"], "1"); XCTAssertEqual(filled["Product"], "Live"); XCTAssertEqual(filled["Type"], "Code error")
        XCTAssertTrue(rows.empty.map(\.0).contains("Branch"), "an id of \"0\" is empty")
        XCTAssertFalse(rows.empty.map(\.0).contains("Product"))
        XCTAssertTrue(rows.lifecycle.isEmpty)
    }

    func testTheTaskSidebarLeavesOutRowsWithoutValue() {
        let task = ZenTaoTaskEntity(execution: "31", estimate: 8, consumed: 2, left: 6, deadline: "2026-12-01", openedBy: "Ryan")
        let rows = ZentaoTaskSectionRows(task: task, ticket: detailTicket("Task", "doing"), parentName: nil, dateFormat: "iso")
        XCTAssertEqual(rows.effort.map(\.0), ["Estimate", "Logged", "Hours left", "Deadline"])
        XCTAssertEqual(rows.effort.first { $0.0 == "Logged" }?.1, "2 h")
        XCTAssertEqual(rows.classification.first { $0.0 == "Progress" }?.1, "25%")
        XCTAssertEqual(rows.lifecycle.map(\.0), ["Opened by"])
    }

    func testFilePreviewKinds() {
        func file(_ title: String, _ ext: String? = nil) -> TicketAttachment { TicketAttachment(id: "1", title: title, url: "u", extension: ext) }
        // A .md upload ZenTao files as txt still previews as Markdown.
        XCTAssertEqual(ZentaoFileKinds.preview(of: file("# Payloads.md", "txt")), .markdown)
        XCTAssertEqual(ZentaoFileKinds.preview(of: file("api.json")), .text)
        XCTAssertEqual(ZentaoFileKinds.preview(of: file("shot.PNG")), .image)
        XCTAssertEqual(ZentaoFileKinds.preview(of: file("repro.mp4")), .video)
        XCTAssertEqual(ZentaoFileKinds.preview(of: file("spec.pdf")), .none)
        XCTAssertEqual(ZentaoFileKinds.preview(of: file("README", "txt")), .text)
        XCTAssertEqual(ZentaoFileKinds.icon(of: file("a.zip")), "doc.zipper")
    }

    func testDownloadsNumberTakenNames() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zt-dl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = ZentaoDownloads.save(Data("x".utf8), as: "shot.png", in: dir), b = ZentaoDownloads.save(Data("y".utf8), as: "shot.png", in: dir)
        XCTAssertEqual(URL(fileURLWithPath: a ?? "").lastPathComponent, "shot.png")
        XCTAssertEqual(URL(fileURLWithPath: b ?? "").lastPathComponent, "shot 2.png")
    }

    func testStreamedAttachmentsCarryTheSessionHeaders() {
        let req = MediaRequest(url: URL(string: "https://z/x.mp4?zentaosid=t")!, headers: ["Cookie": "zentaosid=t", "Token": "t"])
        let asset = ZentaoMedia.asset(req)
        XCTAssertEqual(asset.url, req.url)
    }

    // MARK: Copy actions, person hooks

    func testCopyActionsPutTheRightTextOnTheClipboard() {
        let t = detailTicket("Bug", "active", key: "42", title: "Crash", url: "https://z/bug-view-42.html")
        XCTAssertEqual(ZentaoCopyText.title(t), "Crash"); XCTAssertEqual(ZentaoCopyText.id(t), "#42")
        XCTAssertEqual(ZentaoCopyText.markdownLink(t), "[#42 Crash](https://z/bug-view-42.html)")
        XCTAssertEqual(ZentaoCopyText.entries(t).count, 4)
        let bare = detailTicket("Bug", "active", key: "42", title: "Crash")
        XCTAssertEqual(ZentaoCopyText.markdownLink(bare), "[#42] Crash"); XCTAssertEqual(ZentaoCopyText.entries(bare).count, 3)
    }

    func testThePersonRequestCarriesItsFieldsToTheHostHook() throws {
        let req = try XCTUnwrap(ZentaoPersonRequest.make(accountId: "zt", name: "Thanh", diameter: 18))
        XCTAssertEqual(req.accountId, "zt"); XCTAssertEqual(req.name, "Thanh"); XCTAssertEqual(req.diameter, 18)
    }

    func testModuleNamesLoadOncePerProduct() async {
        let env = DetailEnv()
        let names = await ZentaoModuleNames.bugModules(env.deps, accountId: "zt", productId: "1")
        XCTAssertEqual(names["7"], "Livestream/Share")
        XCTAssertEqual(names["0"], "")
    }
}
