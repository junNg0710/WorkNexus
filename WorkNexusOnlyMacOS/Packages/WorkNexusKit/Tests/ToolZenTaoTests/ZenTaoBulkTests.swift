import CoreDomain
import XCTest
@testable import ToolZenTao

final class ZenTaoBulkTests: XCTestCase {
    private func task(_ id: String, status: String = "doing", assignee: String? = "an", pri: Priority = .medium) -> Ticket {
        Ticket(id: id, accountId: "a", projectId: "p", providerType: .zentao, externalKey: id, title: "T\(id)", body: "", priority: pri,
               status: status == "done" || status == "closed" ? .done : .inprogress, providerStatus: status, sourceHash: id,
               externalType: "Task", assignee: assignee, providerEntity: .zentaoTask(ZenTaoTaskEntity()))
    }

    private func bug(_ id: String, status: String = "active", assignee: String? = "an") -> Ticket {
        Ticket(id: id, accountId: "a", projectId: "p", providerType: .zentao, externalKey: id, title: "B\(id)", body: "", priority: .medium,
               status: status == "closed" ? .done : .todo, providerStatus: status, sourceHash: id, externalType: "Bug", assignee: assignee,
               providerEntity: .zentaoBug(ZenTaoBugEntity()))
    }

    func testAssignSkipsTheFinishedAndTheAlreadyThere() {
        let plan = PlanBulkAction()([task("1"), task("2", assignee: "binh"), task("3", status: "closed"), bug("4", status: "closed"), bug("5")],
                                    .assign(login: "binh"))
        XCTAssertEqual(plan.tickets.map(\.id), ["1", "5"])
        XCTAssertEqual(plan.skipped(.unchanged).map(\.id), ["2"])
        XCTAssertEqual(plan.skipped(.notAllowed).map(\.id), ["3", "4"])
    }

    func testPriorityLeavesOnlyOpenTicketsThatChange() {
        // ZenTao 1..4 is urgent..low.
        let plan = PlanBulkAction()([task("1", pri: .urgent), task("2", pri: .low), task("3", status: "done", pri: .low), bug("4")], .priority(1))
        XCTAssertEqual(plan.tickets.map(\.id), ["2", "4"])
        XCTAssertEqual(plan.skipped(.unchanged).map(\.id), ["1"])
        XCTAssertEqual(plan.skipped(.notAllowed).map(\.id), ["3"])
    }

    func testCloseOnlyWhereZenTaoOffersIt() {
        // A task closes once done or cancelled; a bug once resolved.
        let plan = PlanBulkAction()([task("1", status: "done"), task("2", status: "cancel"), task("3", status: "doing"),
                                     bug("4", status: "resolved"), bug("5", status: "active"), bug("6", status: "closed")], .close)
        XCTAssertEqual(plan.tickets.map(\.id), ["1", "2", "4"])
        XCTAssertEqual(plan.skipped(.notAllowed).map(\.id), ["3", "5", "6"])
    }

    // MARK: Running

    private final class Ops: ZenTaoBulkTicketOps, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [String] = []
        var failing: Set<String> = []
        var calls: [String] { lock.withLock { _calls } }
        private func record(_ what: String, _ t: Ticket) -> Outcome<Void> {
            lock.withLock { _calls.append("\(what):\(t.id)") }
            return failing.contains(t.id) ? .failure(.network("refused \(t.id)")) : .success(())
        }
        func assign(_ ticket: Ticket, to login: String) async -> Outcome<Void> { record("assign \(login)", ticket) }
        func setPriority(_ ticket: Ticket, to pri: Int) async -> Outcome<Void> { record("pri \(pri)", ticket) }
        func close(_ ticket: Ticket) async -> Outcome<Void> { record("close", ticket) }
    }

    func testRunsOneAfterAnotherAndReportsEachOutcome() async {
        let ops = Ops()
        ops.failing = ["2"]
        let plan = PlanBulkAction()([task("1"), task("2"), task("3")], .assign(login: "binh"))
        let seen = LockedList<String>()
        let result = await RunZenTaoBulkAction(ops: ops)(plan, .assign(login: "binh"), progress: { done, total in seen.add("\(done)/\(total)") })
        XCTAssertEqual(ops.calls, ["assign binh:1", "assign binh:2", "assign binh:3"])
        XCTAssertEqual(result.succeeded, ["1", "3"])                    // one ticket refused does not stop the rest
        XCTAssertEqual(result.failed, [ZenTaoBulkFailure(ticketId: "2", message: "refused 2")])
        XCTAssertEqual(seen.items, ["1/3", "2/3", "3/3"])
        XCTAssertFalse(result.isClean)
    }

    func testStoppingLeavesTheRestUntouched() async {
        let ops = Ops()
        let plan = PlanBulkAction()([task("1"), task("2"), task("3")], .priority(1))
        let gate = LockedList<String>()
        let result = await RunZenTaoBulkAction(ops: ops)(plan, .priority(1), shouldContinue: { gate.items.count < 1 },
                                                         progress: { _, _ in gate.add("done") })
        XCTAssertEqual(ops.calls, ["pri 1:1"])
        XCTAssertEqual(result.succeeded, ["1"])
        XCTAssertEqual(result.notRun, ["2", "3"])
    }

    func testAnEmptyPlanDoesNothing() async {
        let ops = Ops()
        let result = await RunZenTaoBulkAction(ops: ops)(ZenTaoBulkPlan(tickets: [], skipped: []), .close)
        XCTAssertTrue(ops.calls.isEmpty)
        XCTAssertTrue(result.isClean)
    }
}

private final class LockedList<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [T] = []
    var items: [T] { lock.withLock { _items } }
    func add(_ item: T) { lock.withLock { _items.append(item) } }
}

// MARK: The adapter over ZenTao's own edit forms and workflow

final class BulkFakeEditor: ZenTaoTicketEditor, @unchecked Sendable {
    var saved: [String] = []
    var loadFailure: Failure?
    func newBugForm(accountId: String, productId: String, copyOf: String?, executionId: String?, taskId: String?) async -> Outcome<BugForm> { .failure(.unexpected("n/a")) }
    func editBugForm(accountId: String, bugId: String) async -> Outcome<BugForm> {
        if let loadFailure { return .failure(loadFailure) }
        var draft = BugDraft(product: "9"); draft.title = "Crash"; draft.pri = 3
        return .success(BugForm(draft: draft, options: BugFormOptions(), kept: ["keep": "me"]))
    }
    func bugOptions(accountId: String, productId: String, projectId: String, executionId: String) async -> Outcome<BugFormOptions> { .failure(.unexpected("n/a")) }
    func bugModules(accountId: String, productId: String) async -> Outcome<[FormOption]> { .success([]) }
    func saveBug(accountId: String, form: BugForm, draft: BugDraft, uid: String) async -> Outcome<String> {
        saved.append("bug pri=\(draft.pri) title=\(draft.title) kept=\(form.kept["keep"] ?? "") uid=\(uid.isEmpty ? "none" : "set")"); return .success("bug-1")
    }
    func newTaskForm(accountId: String, executionId: String, parentId: String?, copyOf: String?) async -> Outcome<TaskForm> { .failure(.unexpected("n/a")) }
    func editTaskForm(accountId: String, taskId: String) async -> Outcome<TaskForm> {
        if let loadFailure { return .failure(loadFailure) }
        var draft = TaskDraft(execution: "5"); draft.name = "Build"; draft.pri = 4; draft.estimate = 8
        return .success(TaskForm(draft: draft, options: TaskFormOptions(), kept: [:]))
    }
    func taskOptions(accountId: String, executionId: String) async -> Outcome<TaskFormOptions> { .failure(.unexpected("n/a")) }
    func saveTask(accountId: String, form: TaskForm, draft: TaskDraft, uid: String) async -> Outcome<String> {
        saved.append("task pri=\(draft.pri) name=\(draft.name) estimate=\(draft.estimate)"); return .success("task-1")
    }
    func loadImage(accountId: String, url: String) async -> Data? { nil }
    func uploadImage(accountId: String, uid: String, bytes: Data, fileName: String) async -> Outcome<String> { .failure(.unexpected("n/a")) }
}

final class ZenTaoBulkOpsTests: XCTestCase {
    private func ops(_ editor: BulkFakeEditor, _ workflow: DetailFakeWorkflow) -> ZentaoBulkOps {
        ZentaoBulkOps(workflow: workflow, editor: editor, assigner: { _, _ in .success(()) })
    }
    private func ticket(_ type: String, _ entity: TicketProviderEntity) -> Ticket {
        Ticket(id: "a:\(type):7", accountId: "a", projectId: "p", providerType: .zentao, externalKey: "7", title: "T", body: "", priority: .medium,
               status: .inprogress, providerStatus: "doing", sourceHash: "h", externalType: type, providerEntity: entity)
    }

    func testPriorityIsSavedThroughTheEditFormKeepingTheRest() async {
        let editor = BulkFakeEditor()
        let sut = ops(editor, DetailFakeWorkflow())
        let task = await sut.setPriority(ticket("Task", .zentaoTask(ZenTaoTaskEntity())), to: 1)
        let bug = await sut.setPriority(ticket("Bug", .zentaoBug(ZenTaoBugEntity())), to: 2)
        XCTAssertNotNil(task.value)
        XCTAssertNotNil(bug.value)
        XCTAssertEqual(editor.saved, ["task pri=1 name=Build estimate=8.0", "bug pri=2 title=Crash kept=me uid=set"])
    }

    func testAFormThatWillNotLoadSavesNothing() async {
        let editor = BulkFakeEditor()
        editor.loadFailure = .network("down")
        let result = await ops(editor, DetailFakeWorkflow()).setPriority(ticket("Task", .zentaoTask(ZenTaoTaskEntity())), to: 1)
        XCTAssertEqual(result.failure?.message, "down")
        XCTAssertTrue(editor.saved.isEmpty)
    }

    func testCloseGoesToTheWorkflowOfItsKind() async {
        let workflow = DetailFakeWorkflow()
        let sut = ops(BulkFakeEditor(), workflow)
        _ = await sut.close(ticket("Task", .zentaoTask(ZenTaoTaskEntity())))
        _ = await sut.close(ticket("Bug", .zentaoBug(ZenTaoBugEntity())))
        XCTAssertEqual(workflow.taskCalls.map { $0.1 }, [.close])
        XCTAssertEqual(workflow.bugCalls, ["close"])
    }
}
