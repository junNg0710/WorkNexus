import CoreDomain
import XCTest
@testable import ToolZenTao

/// Ported from: test/data/zentao_workflow_test.dart, zentao_workflow_actions_test.dart, zentao_language_interceptor_test.dart
final class ZenTaoWorkflowTests: XCTestCase {
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 15, minute: 30))!
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func makeWorkflow(_ reply: @escaping (StubRequest) -> StubResponse = { _ in .json(["result": "success"]) }) -> (ZenTaoWorkflow, StubServer) {
        let server = StubServer { req in req.path.hasSuffix("/tokens") ? .json(["token": "t"]) : reply(req) }
        let client = makeClient(server, base: "https://z.example.com/zentao")
        return (ZenTaoWorkflow(client: client, now: { self.now }), server)
    }

    private func sent(_ server: StubServer, _ path: String) throws -> StubRequest { try XCTUnwrap(server.requests.last { $0.path.contains(path) }) }

    private func task(assignee: String? = nil, consumed: Double? = nil, realStarted: Date? = nil) -> Ticket {
        var t = bugTicket(key: "12", type: "Task", entity: .zentaoTask(ZenTaoTaskEntity(consumed: consumed, realStarted: realStarted)), status: "wait")
        t.assignee = assignee
        return t
    }

    func testClosingABugPostsItsNoteToBugClose() async throws {
        let (workflow, server) = makeWorkflow()
        try await workflow.closeBug("4302", comment: " verified ")
        let req = try sent(server, "bug-close-4302")
        XCTAssertEqual(req.field("comment"), "verified")
        XCTAssertNotNil(req.field("uid"))
    }

    func testStartingSendsTheNewTotalLoggedAndKeepsTheAssignee() async throws {
        let (workflow, server) = makeWorkflow()
        try await workflow.runTaskAction(task(assignee: "lan", consumed: 2), .start, ZenTaoTaskActionInput(spent: 1.5, left: 4))
        let req = try sent(server, "task-start-12")
        XCTAssertEqual(req.field("consumed"), "3.5")
        XCTAssertEqual(req.field("left"), "4")
        XCTAssertEqual(req.field("realStarted"), "2026-10-09 15:30:00")
        XCTAssertEqual(req.field("assignedTo"), "lan")
        XCTAssertNil(req.form["comment"])
    }

    func testContinuingKeepsWhenTheTaskReallyStarted() async throws {
        let (workflow, server) = makeWorkflow()
        try await workflow.runTaskAction(task(realStarted: date(2026, 10, 1, 9)), .restart, ZenTaoTaskActionInput(left: 2, assignee: "an"))
        let req = try sent(server, "task-restart-12")
        XCTAssertEqual(req.field("realStarted"), "2026-10-01 09:00:00")
        XCTAssertEqual(req.field("assignedTo"), "an")
    }

    func testFinishingSendsThisTimeAndTheTotalDatedNow() async throws {
        let (workflow, server) = makeWorkflow()
        try await workflow.runTaskAction(task(consumed: 3, realStarted: date(2026, 10, 8, 10)), .finish, ZenTaoTaskActionInput(spent: 2, comment: "done"))
        let req = try sent(server, "task-finish-12")
        XCTAssertEqual(req.field("currentConsumed"), "2")
        XCTAssertEqual(req.field("consumed"), "5")
        XCTAssertEqual(req.field("realStarted"), "2026-10-08 10:00:00")
        XCTAssertEqual(req.field("finishedDate"), "2026-10-09 15:30:00")
        XCTAssertEqual(req.field("comment"), "done")
        // Left out, ZenTao hands the task back to its creator.
        XCTAssertNil(req.form["assignedTo"])
        XCTAssertNil(req.form["left"])
    }

    func testStartingSendsTheBeginPickedInTheForm() async throws {
        let (workflow, server) = makeWorkflow()
        try await workflow.runTaskAction(task(), .start, ZenTaoTaskActionInput(left: 4, began: date(2026, 10, 9, 8, 15)))
        XCTAssertEqual(try sent(server, "task-start-12").field("realStarted"), "2026-10-09 08:15:00")
    }

    func testFinishingSendsThePickedBeginAndEndWithItsFiles() async throws {
        let (workflow, server) = makeWorkflow()
        try await workflow.runTaskAction(task(), .finish, ZenTaoTaskActionInput(
            spent: 1, assignee: "evan", began: date(2026, 10, 13, 17, 48), ended: date(2026, 10, 13, 18, 49),
            files: [DraftFile(name: "log.txt", bytes: Data([1]))]))
        let req = try sent(server, "task-finish-12")
        XCTAssertTrue(req.header("Content-Type")?.hasPrefix("multipart/form-data") == true)
        let body = req.bodyText
        XCTAssertTrue(body.contains("name=\"realStarted\"\r\n\r\n2026-10-13 17:48:00"))
        XCTAssertTrue(body.contains("name=\"finishedDate\"\r\n\r\n2026-10-13 18:49:00"))
        XCTAssertTrue(body.contains("name=\"assignedTo\"\r\n\r\nevan"))
        XCTAssertTrue(body.contains("name=\"labels[]\"\r\n\r\nlog.txt"))
        XCTAssertTrue(body.contains("name=\"files[]\"; filename=\"log.txt\""))
    }

    func testReopeningSendsTheHoursLeftAndGivesTheTaskToMe() async throws {
        let (workflow, server) = makeWorkflow()
        try await workflow.runTaskAction(task(), .activate, ZenTaoTaskActionInput(left: 1))
        let req = try sent(server, "task-activate-12")
        XCTAssertEqual(req.field("left"), "1")
        XCTAssertEqual(req.field("assignedTo"), "me")
    }

    func testPauseCloseAndCancelSendOnlyANote() async throws {
        for action in [ZenTaoTaskAction.pause, .close, .cancel] {
            let (workflow, server) = makeWorkflow()
            try await workflow.runTaskAction(task(consumed: 1), action, ZenTaoTaskActionInput(spent: 9, left: 9, comment: "why"))
            let req = try sent(server, "task-\(action.name)-12")
            XCTAssertEqual(Set(req.form.keys), ["uid", "comment"], action.name)
        }
    }

    func testARefusalWrappedThe18WayStillFailsWithItsReason() async throws {
        // 18.x wraps every .json reply as {status: success, data: '<json>'} - a refused action too.
        let (workflow, _) = makeWorkflow { _ in
            .json(wrapped(["result": "fail", "message": ["left": ["Left must be more than 0"]] as JSON] as JSON))
        }
        do {
            try await workflow.runTaskAction(task(), .activate, ZenTaoTaskActionInput(left: 1))
            XCTFail("a refusal must throw")
        } catch let e as ZenTaoError {
            XCTAssertTrue(e.message.contains("Left must be more than 0"))
            XCTAssertEqual(e.workflowFailure, .validation(e.message))
        }
    }

    func testAn18SuccessAPageToGoToPasses() async throws {
        let (workflow, _) = makeWorkflow { _ in .json(wrapped(["locate": "/zentao/task-view-12.html"])) }
        try await workflow.runTaskAction(task(), .pause, ZenTaoTaskActionInput())
    }

    func testA20RefusalFails() async throws {
        let (workflow, _) = makeWorkflow { _ in .json(["result": "fail", "message": "Task is already started"]) }
        do {
            try await workflow.runTaskAction(task(), .start, ZenTaoTaskActionInput(left: 1))
            XCTFail("a refusal must throw")
        } catch let e as ZenTaoError { XCTAssertTrue(e.message.contains("Task is already started")) }
    }

    func testAReplyThatIsNotJsonFailsAndASignedOutReplyFails() async throws {
        let (html, _) = makeWorkflow { _ in .html("<html>login</html>") }
        do { try await html.closeBug("1"); XCTFail("html is a failure") } catch is ZenTaoError {}
        let (signedOut, _) = makeWorkflow { _ in .json(wrapped(["locate": "/user-login.html"])) }
        do { try await signedOut.closeBug("1"); XCTFail("login redirect is a failure") } catch is ZenTaoError {}
    }

    func testHoursAreSentAsZenTaoWritesThem() {
        XCTAssertEqual(zentaoHours(2), "2")
        XCTAssertEqual(zentaoHours(2.5), "2.5")
        XCTAssertEqual(zentaoHours(0.1 + 0.2), "0.3")
    }

    // MARK: ZenTaoWorkflowActions (optimistic outcomes)

    private final class RecordingRunner: ZenTaoOptimisticRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var shownTickets: [Ticket] = []
        var result: Outcome<Void> = .success(())
        var runAction = false
        var shown: [Ticket] { lock.withLock { shownTickets } }
        func runOptimisticAction(_ original: Ticket, _ optimistic: Ticket, _ action: @escaping @Sendable () async -> Outcome<Void>) async -> Outcome<Void> {
            lock.withLock { shownTickets.append(optimistic) }
            return runAction ? await action() : result
        }
    }

    private struct NoAdapters: ZenTaoAdapterProvider, ZenTaoClientProvider {
        var adapter: ProviderAdapter?
        var client: ZenTaoClient?
        func adapter(accountId: String) async -> ProviderAdapter? { adapter }
        func zenTaoClient(accountId: String) async -> ZenTaoClient? { client }
    }

    func testEachTaskActionShowsItsOutcomeAtOnce() async {
        let runner = RecordingRunner()
        let actions = ZenTaoWorkflowActions(runner: runner, adapters: NoAdapters(), clients: NoAdapters())
        let expected: [ZenTaoTaskAction: (String, UnifiedStatus)] = [
            .start: ("doing", .inprogress), .restart: ("doing", .inprogress), .activate: ("doing", .inprogress),
            .pause: ("pause", .blocked), .finish: ("done", .review), .close: ("closed", .done), .cancel: ("cancel", .done),
        ]
        for (action, (raw, status)) in expected {
            _ = await actions.runTaskAction(task(), action, ZenTaoTaskActionInput(left: 1))
            let shown = runner.shown.last
            XCTAssertEqual(shown?.providerStatus, raw, action.name)
            XCTAssertEqual(shown?.status, status, action.name)
        }
    }

    func testClosingABugShowsItClosedAtOnce() async {
        let runner = RecordingRunner()
        let actions = ZenTaoWorkflowActions(runner: runner, adapters: NoAdapters(), clients: NoAdapters())
        _ = await actions.closeBug(bugTicket(status: "resolved"), comment: "ok")
        XCTAssertEqual(runner.shown.last?.providerStatus, "closed")
        XCTAssertEqual(runner.shown.last?.status, .done)
    }

    func testConfirmAndReopenShowTheirOptimisticState() async {
        let runner = RecordingRunner()
        let actions = ZenTaoWorkflowActions(runner: runner, adapters: NoAdapters(), clients: NoAdapters())
        _ = await actions.confirmBug(task(), assignee: "an", comment: "c")
        XCTAssertEqual(runner.shown.last?.providerStatus, "active")
        XCTAssertEqual(runner.shown.last?.assignee, "an")
        _ = await actions.activateBug(task(), build: "7", assignee: nil, comment: nil)
        XCTAssertEqual(runner.shown.last?.providerStatus, "active")
        XCTAssertEqual(runner.shown.last?.status, .todo)
    }

    func testResolvingShowsTheBugAwaitingVerificationWithItsResolution() async {
        let runner = RecordingRunner()
        let actions = ZenTaoWorkflowActions(runner: runner, adapters: NoAdapters(), clients: NoAdapters())
        let bug = bugTicket(status: "active", labels: ["resolution:fixed", "ui"])
        _ = await actions.resolveBug(bug, resolution: "postponed", build: nil, assignee: nil, comment: nil)
        let resolved = try! XCTUnwrap(runner.shown.last)
        XCTAssertEqual(resolved.providerStatus, "resolved")
        XCTAssertEqual(resolved.status, .review)
        XCTAssertEqual(resolved.labels, ["ui", "resolution:postponed"])
        _ = await actions.activateBug(resolved, build: nil, assignee: nil, comment: nil)
        XCTAssertEqual(runner.shown.last?.labels, ["ui"])
    }

    func testAnActionWithoutACredentialedAccountFailsAndRestoresViaTheRunner() async {
        let runner = RecordingRunner()
        runner.runAction = true
        let actions = ZenTaoWorkflowActions(runner: runner, adapters: NoAdapters(), clients: NoAdapters())
        let bug = await actions.confirmBug(bugTicket(), assignee: nil, comment: nil)
        XCTAssertEqual(bug.failure, .auth("No stored credentials for this account"))
        let task = await actions.runTaskAction(self.task(), .start, ZenTaoTaskActionInput(left: 1))
        XCTAssertEqual(task.failure, .auth("ZenTao account is not signed in"))
    }

    func testARunnerActionReachesZenTaoThroughThePooledClient() async throws {
        let server = StubServer { req in req.path.hasSuffix("/tokens") ? .json(["token": "t"]) : .json(["result": "success"]) }
        let runner = RecordingRunner()
        runner.runAction = true
        let pool = NoAdapters(adapter: makeAdapter(server), client: makeClient(server))
        let actions = ZenTaoWorkflowActions(runner: runner, adapters: pool, clients: pool)
        let closed = await actions.closeBug(bugTicket(status: "resolved"), comment: nil)
        XCTAssertNotNil(closed.value)
        XCTAssertTrue(server.requests.contains { $0.path.contains("bug-close-4302") })
        let resolved = await actions.resolveBug(bugTicket(), resolution: "fixed", build: nil, assignee: nil, comment: nil)
        XCTAssertNotNil(resolved.value)
        XCTAssertTrue(server.requests.contains { $0.path.contains("bug-resolve-4302") })
    }

    // MARK: Language interceptor

    private func languageCookie(host: String, url: String, cookie: String? = nil) -> String? {
        var request = ZenTaoRequest(url: URL(string: url)!)
        if let cookie { request.headers["Cookie"] = cookie }
        ZenTaoLanguageInterceptor(host: { host }).apply(&request)
        return ZenTaoHeaders.get(request.headers, "Cookie")
    }

    func testAsksTheZenTaoServerForEnglishBesideTheSession() {
        XCTAssertEqual(languageCookie(host: "zentao.example.com", url: "https://zentao.example.com/zentao/bug-assignTo-6492.json", cookie: "zentaosid=abc"),
                       "zentaosid=abc; lang=en")
        XCTAssertEqual(languageCookie(host: "zentao.example.com", url: "https://zentao.example.com/zentao/api.php/v1/bugs"), "lang=en")
    }

    func testOtherHostsGetNoCookie() {
        XCTAssertNil(languageCookie(host: "zentao.example.com", url: "https://cdn.example.com/avatar.png"))
    }

    func testACallersOwnLangCookieIsKept() {
        XCTAssertEqual(languageCookie(host: "zentao.example.com", url: "https://zentao.example.com/zentao/index.html", cookie: "zentaosid=abc; lang=zh-cn"),
                       "zentaosid=abc; lang=zh-cn")
    }
}
