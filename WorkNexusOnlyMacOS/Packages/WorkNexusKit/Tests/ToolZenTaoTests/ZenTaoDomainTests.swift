import CoreDomain
import XCTest
@testable import ToolZenTao

/// Ported from: test/domain/{zentao_action_usecases,build_zentao_module_tree,zentao_doc_usecases}_test.dart,
/// test/unit/zentao_usecases_test.dart, test/data/task_bugs_coverage_test.dart
final class ZenTaoDomainTests: XCTestCase {
    private func ticket(_ type: String, _ raw: String, status: UnifiedStatus = .todo, entity: TicketProviderEntity? = nil) -> Ticket {
        Ticket(id: "zt:1", accountId: "zt", projectId: "zt:P", providerType: .zentao, externalKey: "1", title: "t", body: "",
               priority: .medium, status: status, providerStatus: raw, sourceHash: "h", externalType: type, providerEntity: entity)
    }

    // MARK: Bug actions

    func testANewBugIsConfirmedOrResolved() {
        let menu = ListZenTaoBugActions()(ticket("Bug", "active", status: .inbox))
        XCTAssertTrue(menu.canAssign)
        XCTAssertEqual(menu.actions, [.confirm, .resolve])
    }

    func testAConfirmedBugIsOnlyResolvedAResolvedOneClosedOrReopenedAClosedOneOnlyReopened() {
        let list = ListZenTaoBugActions()
        XCTAssertEqual(list(ticket("Bug", "active")).actions, [.resolve])
        let resolved = list(ticket("Bug", "resolved", status: .review))
        XCTAssertTrue(resolved.canAssign)
        XCTAssertEqual(resolved.actions, [.close, .activate])
        let closed = list(ticket("Bug", "closed", status: .done))
        XCTAssertFalse(closed.canAssign)
        XCTAssertEqual(closed.actions, [.activate])
    }

    func testTheMainButtonIsTheNextStepOfTheBug() {
        let list = ListZenTaoBugActions()
        XCTAssertEqual(list(ticket("Bug", "active", status: .inbox)).primary, .confirm)
        XCTAssertEqual(list(ticket("Bug", "active", status: .todo)).primary, .resolve)
        XCTAssertEqual(list(ticket("Bug", "resolved", status: .review)).primary, .close)
        XCTAssertEqual(list(ticket("Bug", "closed", status: .done)).primary, .activate)
        XCTAssertNil(list(ticket("Bug", "")).primary)
    }

    // MARK: Task actions

    private func taskActions(_ raw: String, isParent: Bool = false) -> [ZenTaoTaskAction] {
        ListZenTaoTaskActions()(ticket("Task", raw, entity: .zentaoTask(ZenTaoTaskEntity(isParent: isParent)))).actions
    }

    func testEachTaskStatusOffersWhatZenTaoAllows() {
        XCTAssertEqual(taskActions("wait"), [.start, .finish, .cancel])
        XCTAssertEqual(taskActions("doing"), [.pause, .finish, .cancel])
        XCTAssertEqual(taskActions("pause"), [.restart, .finish, .cancel])
        XCTAssertEqual(taskActions("done"), [.activate, .close])
        XCTAssertEqual(taskActions("cancel"), [.activate, .close])
        XCTAssertEqual(taskActions("closed"), [.activate])
    }

    func testTheTaskMainButtonMovesTheTaskForward() {
        func primary(_ raw: String, isParent: Bool = false) -> ZenTaoTaskAction? {
            ListZenTaoTaskActions()(ticket("Task", raw, entity: .zentaoTask(ZenTaoTaskEntity(isParent: isParent)))).primary
        }
        XCTAssertEqual(primary("wait"), .start)
        XCTAssertEqual(primary("doing"), .finish)
        XCTAssertEqual(primary("pause"), .restart)
        XCTAssertEqual(primary("done"), .close)
        XCTAssertEqual(primary("cancel"), .close)
        XCTAssertEqual(primary("closed"), .activate)
        // A parent task in progress can only be cancelled - never the main button.
        XCTAssertNil(primary("doing", isParent: true))
    }

    func testAClosedOrCancelledTaskIsNotReassignedAndAParentFollowsItsSubtasks() {
        let list = ListZenTaoTaskActions()
        for raw in ["closed", "cancel"] { XCTAssertFalse(list(ticket("Task", raw)).canAssign, raw) }
        XCTAssertTrue(list(ticket("Task", "doing")).canAssign)
        XCTAssertEqual(taskActions("doing", isParent: true), [.cancel])
        XCTAssertEqual(taskActions("pause", isParent: true), [.restart, .cancel])
        XCTAssertTrue(taskActions("done", isParent: true).isEmpty)
        let parent = ticket("Task", "doing", entity: .zentaoTask(ZenTaoTaskEntity(isParent: true)))
        XCTAssertTrue(list(parent).canAssign)              // ZenTao 21.x lets a parent task change hands
        XCTAssertFalse(list(ticket("Task", "closed", entity: .zentaoTask(ZenTaoTaskEntity(isParent: true)))).canAssign)
    }

    // MARK: Input checks

    func testAssignLeftRefusesNoHoursNaNAndNegatives() {
        let check = CheckZenTaoAssignLeft()
        XCTAssertEqual(check(0), .leftRequired)
        XCTAssertEqual(check(.nan), .invalidHours)
        XCTAssertEqual(check(-1), .invalidHours)
        XCTAssertNil(check(1.5))
    }

    private func problem(_ action: ZenTaoTaskAction, spent: Double = 0, left: Double = 0, logged: Double = 0) -> ZenTaoTaskInputProblem? {
        CheckZenTaoTaskInput()(action: action, input: ZenTaoTaskActionInput(spent: spent, left: left), logged: logged)
    }

    func testStartContinueAndReopenNeedHoursLeft() {
        for action in [ZenTaoTaskAction.start, .restart, .activate] {
            XCTAssertEqual(problem(action), .leftRequired, action.name)
            XCTAssertNil(problem(action, left: 2), action.name)
        }
    }

    func testFinishingNeedsHoursWorkedUnlessSomeAreLogged() {
        XCTAssertEqual(problem(.finish), .spentRequired)
        XCTAssertNil(problem(.finish, spent: 1))
        XCTAssertNil(problem(.finish, logged: 3))
    }

    func testHoursMustBeANumberZeroOrMore() {
        XCTAssertEqual(problem(.start, spent: -1, left: 2), .invalidHours)
        XCTAssertEqual(problem(.activate, left: .nan), .invalidHours)
    }

    func testAFinishCannotBeDatedBeforeTheBegin() {
        func finish(_ ended: Date) -> ZenTaoTaskInputProblem? {
            let began = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 17, minute: 48))!
            return CheckZenTaoTaskInput()(action: .finish, input: ZenTaoTaskActionInput(spent: 1, began: began, ended: ended), logged: 0)
        }
        func at(_ h: Int, _ m: Int) -> Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: h, minute: m))! }
        XCTAssertEqual(finish(at(17, 0)), .endBeforeBegin)
        XCTAssertNil(finish(at(17, 48)))
        XCTAssertNil(finish(at(18, 49)))
    }

    func testPauseCloseAndCancelAskForNoHours() {
        for action in [ZenTaoTaskAction.pause, .close, .cancel] { XCTAssertNil(problem(action, spent: -1, left: -1), action.name) }
    }

    // MARK: Create actions, effort, due date

    func testCreateActions() {
        let list = ListZenTaoCreateActions()
        XCTAssertEqual(list(ticket("Bug", "active")), [.copyBug])
        XCTAssertEqual(list(ticket("Task", "doing", entity: .zentaoTask(ZenTaoTaskEntity(execution: "31")))), [.copyTask, .subtask, .bugFromTask])
        let none: [(String, ZenTaoTaskEntity)] = [
            ("doing", ZenTaoTaskEntity(parentId: "7", execution: "31")), ("closed", ZenTaoTaskEntity(execution: "31")), ("doing", ZenTaoTaskEntity()),
        ]
        for (raw, entity) in none {
            XCTAssertEqual(list(ticket("Task", raw, entity: .zentaoTask(entity))), [.copyTask, .bugFromTask], raw)
        }
        XCTAssertTrue(list(ticket("Story", "active")).isEmpty)
    }

    func testTaskEffortProgressIsLoggedOverLoggedPlusLeft() {
        let summarize = SummarizeTaskEffort()
        XCTAssertNil(summarize(ZenTaoTaskEntity()))
        let effort = summarize(ZenTaoTaskEntity(estimate: 8, consumed: 3, left: 1))
        XCTAssertEqual(effort, TaskEffort(estimate: 8, consumed: 3, left: 1, progress: 0.75))
        XCTAssertEqual(summarize(ZenTaoTaskEntity(estimate: 4))?.progress, 0)
        XCTAssertEqual(summarize(ZenTaoTaskEntity(estimate: -2, consumed: .nan, left: 1))?.consumed, 0)
    }

    func testDueThisWeekRunsMondayThroughSunday() {
        func at(_ d: Int, _ h: Int = 12) -> Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))! }
        let thursday = at(15)                       // 2026-10-15 is a Thursday
        let due = IsDueThisWeek()
        XCTAssertTrue(due(at(12, 0), now: thursday))      // Monday 00:00
        XCTAssertTrue(due(at(18, 23), now: thursday))     // Sunday evening
        XCTAssertFalse(due(at(11, 23), now: thursday))
        XCTAssertFalse(due(at(19, 0), now: thursday))
    }

    func testDeadlineComesFromTheEntityOrALabel() {
        XCTAssertNotNil(extractZenTaoDeadline(ticket("Bug", "active", entity: .zentaoBug(ZenTaoBugEntity(deadline: "2026-10-20")))))
        XCTAssertNotNil(extractZenTaoDeadline(ticket("Task", "wait", entity: .zentaoTask(ZenTaoTaskEntity(deadline: "2026-10-20")))))
        var labelled = ticket("Bug", "active")
        labelled.labels = ["deadline:2026-10-20"]
        XCTAssertNotNil(extractZenTaoDeadline(labelled))
        XCTAssertNil(extractZenTaoDeadline(ticket("Bug", "active")))
    }

    // MARK: Columns, streams, labels

    func testBugColumns() {
        func column(_ raw: String, _ status: UnifiedStatus = .todo, labels: [String] = []) -> ZenTaoBugColumn {
            var t = ticket("Bug", raw, status: status)
            t.labels = labels
            return zentaoBugColumnFor(t)
        }
        XCTAssertEqual(column("active", .inbox), .newUnconfirmed)
        XCTAssertEqual(column("active"), .confirmedToFix)
        XCTAssertEqual(column("resolved", .review), .resolvedVerify)
        XCTAssertEqual(column("resolved", .review, labels: ["resolution:fixed"]), .resolvedVerify)
        XCTAssertEqual(column("resolved", .review, labels: ["resolution:postponed"]), .postponed)
        XCTAssertEqual(column("resolved", .review, labels: ["resolution:bydesign"]), .nonFix)
        XCTAssertEqual(column("closed", .done), .closed)
        XCTAssertEqual(ZenTaoBugColumn.columns, [.newUnconfirmed, .confirmedToFix, .resolvedVerify, .postponed, .nonFix, .closed])
    }

    func testTaskColumnsAndStatusOf() {
        XCTAssertEqual(zentaoTaskColumnFor(ticket("Task", "doing")), .inProgress)
        XCTAssertEqual(zentaoTaskColumnFor(ticket("Task", "pause")), .paused)
        XCTAssertEqual(zentaoTaskColumnFor(ticket("Task", "done")), .doneVerify)
        XCTAssertEqual(zentaoTaskColumnFor(ticket("Task", "cancel")), .canceled)
        XCTAssertEqual(zentaoTaskColumnFor(ticket("Task", "?", status: .blocked)), .paused)
        XCTAssertEqual(zentaoTaskColumnFor(ticket("Task", "wait")), .notStarted)
        XCTAssertEqual(ZenTaoTaskColumn.doneVerify.browseType, "done")
        XCTAssertEqual(zentaoStatusOf(ticket("Task", "doing")), "inProgress")
        XCTAssertEqual(zentaoStatusOf(ticket("Bug", "closed", status: .done)), "closed")
        XCTAssertNil(zentaoStatusOf(ticket("Story", "active")))
        var gl = ticket("Bug", "active")
        gl.providerType = .gitlab
        XCTAssertNil(zentaoStatusOf(gl))
    }

    func testBugStreamsAndBrowseTypes() {
        XCTAssertEqual(ZenTaoBugStream.of(.newUnconfirmed), .unconfirmed)
        XCTAssertEqual(ZenTaoBugStream.of(.confirmedToFix), .unresolved)
        XCTAssertEqual(ZenTaoBugStream.of(.postponed), .toClose)
        XCTAssertEqual(ZenTaoBugStream.of(.closed), .all)
        XCTAssertEqual(ZenTaoBugStream.of(.closed, related: true), .relatedToMe)
        XCTAssertEqual(ZenTaoBugStream.relatedToMe.codes, ["assigntome", "openedbyme", "resolvedbyme"])
        XCTAssertEqual(ZenTaoBugStream.toClose.code, "toclosed")
        XCTAssertEqual(ZenTaoBugBrowseType.allCases.map(\.code), ["all", "unclosed", "openedbyme", "assigntome", "resolvedbyme", "assignedbyme"])
    }

    func testCodedFieldLabels() {
        XCTAssertEqual(zentaoSeverityLabel(2), "Major")
        XCTAssertNil(zentaoSeverityLabel(9))
        XCTAssertEqual(zentaoBugTypeLabel("codeerror"), "Code error")
        XCTAssertEqual(zentaoBugTypeLabel("weird"), "Weird")
        XCTAssertEqual(zentaoTaskTypeLabel("devel"), "Development")
        XCTAssertEqual(zentaoResolutionLabel("notrepro"), "Irreproducible")
        XCTAssertEqual(zentaoResolutionLabel(" Custom "), "Custom")
        XCTAssertNil(zentaoResolutionLabel(" "))
        XCTAssertEqual(zentaoBugTypeCodes.first, "codeerror")
        XCTAssertEqual(zentaoResolutionCodes.first, "bydesign")
        XCTAssertEqual(formatFileSize(39_124_123), "37.3 MB")
        XCTAssertEqual(formatFileSize(512), "512 B")
        XCTAssertNil(formatFileSize(-1))
    }

    // MARK: Module tree, task bugs

    private func bug(_ id: String, module: String, task: String? = nil) -> Ticket {
        Ticket(id: id, accountId: "zt", projectId: "p", providerType: .zentao, externalKey: id, title: "Bug \(id)", body: "", priority: .medium,
               status: .todo, providerStatus: "active", sourceHash: "h", providerEntity: .zentaoBug(ZenTaoBugEntity(module: module, task: task)))
    }

    private var modulePaths: [(id: String, path: String)] {
        [("0", ""), ("1", "Live stream"), ("2", "Live stream/Share"), ("3", "Feed"), ("4", "Location")]
    }

    private func names(_ tree: ZenTaoModuleTree) -> [String] { tree.nodes.map { "\(String(repeating: "  ", count: $0.depth))\($0.name):\($0.count)" } }

    func testModulesAreNamedByTheirLastPathPartIndentedAndCounted() {
        let bugs = [bug("a", module: "2"), bug("b", module: "2"), bug("c", module: "3"), bug("d", module: "0")]
        let tree = BuildZenTaoModuleTree()(paths: modulePaths, tickets: bugs)
        XCTAssertEqual(names(tree), ["Live stream:0", "  Share:2", "Feed:1", "Location:0"])
        XCTAssertEqual(tree.total, 4)
        XCTAssertEqual(names(BuildZenTaoModuleTree()(paths: modulePaths, tickets: bugs, hideEmpty: true)), ["Live stream:0", "  Share:2", "Feed:1"])
        XCTAssertEqual(names(BuildZenTaoModuleTree()(paths: modulePaths, tickets: bugs, hideEmpty: true, selected: "4")),
                       ["Live stream:0", "  Share:2", "Feed:1", "Location:0"])
        XCTAssertEqual(zentaoModuleOf(bugs[0]), "2")
    }

    func testListTaskBugsPicksTheTasksBugsNewestFirst() {
        let task = ticket("Task", "doing")
        let tickets = [bug("5", module: "0", task: "1"), bug("9", module: "0", task: "1"), bug("7", module: "0", task: "2")]
        XCTAssertEqual(ListTaskBugs()(task: task, tickets: tickets).map(\.externalKey), ["9", "5"])
    }

    func testATaskBugsReadCoversWhatItStoppedAt() {
        let at = Date(timeIntervalSince1970: 1_000_000)
        let soon = at.addingTimeInterval(60), late = at.addingTimeInterval(TaskBugsCoverage.ttl)
        let sorted = TaskBugsCoverage(at: at, above: 11000, tasks: [11548])
        XCTAssertTrue(sorted.covers(11548, now: soon))
        XCTAssertTrue(sorted.covers(11001, now: soon))
        XCTAssertFalse(sorted.covers(11000, now: soon))
        XCTAssertFalse(sorted.covers(9000, now: soon))
        XCTAssertTrue(TaskBugsCoverage(at: at, complete: true).covers(1, now: soon))
        let unsorted = TaskBugsCoverage(at: at, tasks: [8])
        XCTAssertTrue(unsorted.covers(8, now: soon))
        XCTAssertFalse(unsorted.covers(9, now: soon))
        XCTAssertFalse(TaskBugsCoverage(at: at, complete: true).covers(1, now: late))
    }

    // MARK: Docs + profile use cases

    func testFilterDocLibsMatchesTheNameCaseInsensitivelyInOrder() {
        let libs = [ZenTaoDocLib(id: "1", name: "Notification"), ZenTaoDocLib(id: "2", name: "Payment API"), ZenTaoDocLib(id: "3", name: "notes")]
        let filter = FilterZenTaoDocLibs()
        XCTAssertEqual(filter(libs, query: "  "), libs)
        XCTAssertEqual(filter(libs, query: " NOT ").map(\.id), ["1", "3"])
    }

    private final class PinsRepository: ZenTaoDocRepository, @unchecked Sendable {
        var pins = ZenTaoDocPins()
        var saved: [ZenTaoDocPins] = []
        func watchPins(accountId: String) -> AsyncStream<ZenTaoDocPins> { let p = pins; return AsyncStream { $0.yield(p); $0.finish() } }
        func savePins(accountId: String, pins: ZenTaoDocPins) async -> Outcome<Void> { saved.append(pins); return .success(()) }
        func watchLibs(accountId: String) -> AsyncStream<[ZenTaoDocLib]> { AsyncStream { $0.finish() } }
        func watchDocs(accountId: String, libId: String) -> AsyncStream<[ZenTaoDocSummary]> { AsyncStream { $0.finish() } }
        func watchDoc(accountId: String, docId: String) -> AsyncStream<ZenTaoDoc?> { AsyncStream { $0.finish() } }
        func refreshLibs(account: Account) async -> Outcome<Void> { .success(()) }
        func refreshDocs(account: Account, libId: String) async -> Outcome<Void> { .success(()) }
        func refreshDoc(account: Account, docId: String) async -> Outcome<Void> { .success(()) }
        func watchHistory(accountId: String, docId: String) -> AsyncStream<[ZenTaoDocAction]> { AsyncStream { $0.finish() } }
        func refreshHistory(account: Account, docId: String) async -> Outcome<Void> { .success(()) }
        func fetchImage(account: Account, url: String) async -> Data? { nil }
        func readFile(account: Account, file: TicketAttachment) async -> Outcome<Data> { .failure(.notFound("x")) }
        func saveFile(account: Account, file: TicketAttachment) async -> Outcome<String> { .failure(.notFound("x")) }
        func readBackup(accountId: String, docId: String) async -> Outcome<String> { .failure(.notFound("x")) }
        func saveText(fileName: String, text: String) async -> Outcome<String> { .failure(.notFound("x")) }
    }

    func testTogglingAPinPinsThenUnpins() async {
        let repo = PinsRepository()
        let lib = ZenTaoDocLib(id: "247", name: "Notification")
        let doc = ZenTaoDocSummary(id: "115", title: "Payloads", libId: "247")
        _ = await ToggleZenTaoDocPin(repo)(accountId: "a1", lib: lib)
        XCTAssertEqual(repo.saved.last?.libs, [lib])
        repo.pins = ZenTaoDocPins(libs: [lib], docs: [doc])
        _ = await ToggleZenTaoDocPin(repo)(accountId: "a1", doc: doc)
        XCTAssertEqual(repo.saved.last, ZenTaoDocPins(libs: [lib], docs: []))
    }

    private final class ProfileRepository: ZenTaoProfileRepository, @unchecked Sendable {
        var updates: [ZenTaoProfileUpdate] = []
        func watch(accountId: String) -> AsyncStream<ZenTaoProfile?> { AsyncStream { $0.finish() } }
        func watchDepartments(accountId: String) -> AsyncStream<[ZenTaoDepartment]> { AsyncStream { $0.finish() } }
        func refresh(account: Account) async -> Outcome<ZenTaoProfile> { .failure(.notFound("x")) }
        func update(account: Account, changes: ZenTaoProfileUpdate) async -> Outcome<ZenTaoProfile> {
            updates.append(changes)
            return .success(ZenTaoProfile(accountId: account.id, account: "a", realname: changes.realname))
        }
    }

    func testUpdateProfileValidatesAndTrimsBeforeSaving() async {
        let repo = ProfileRepository()
        let update = UpdateZenTaoProfile(repo)
        let account = Account(id: "a1", workspaceId: "w", providerType: .zentao, handle: "t")
        let blank = await update(account: account, changes: ZenTaoProfileUpdate(realname: " ", email: "", mobile: "", phone: ""))
        XCTAssertEqual(blank.failure, .parse("Name is required"))
        let bad = await update(account: account, changes: ZenTaoProfileUpdate(realname: "T", email: "nope", mobile: "", phone: ""))
        XCTAssertEqual(bad.failure, .parse("Invalid email address"))
        let ok = await update(account: account, changes: ZenTaoProfileUpdate(realname: " Thanh ", email: " t@x.io ", mobile: " 1 ", phone: " 2 "))
        XCTAssertEqual(ok.value?.realname, "Thanh")
        XCTAssertEqual(repo.updates, [ZenTaoProfileUpdate(realname: "Thanh", email: "t@x.io", mobile: "1", phone: "2")])
    }
    // MARK: Export

    private final class ExportRepository: ZenTaoDocRepository, @unchecked Sendable {
        var savedText: [(String, String)] = []
        var backup: Outcome<String> = .success("{\"id\": 50}")
        func saveText(fileName: String, text: String) async -> Outcome<String> { savedText.append((fileName, text)); return .success("/Downloads/x") }
        func readBackup(accountId: String, docId: String) async -> Outcome<String> { backup }
        func watchPins(accountId: String) -> AsyncStream<ZenTaoDocPins> { AsyncStream { $0.finish() } }
        func savePins(accountId: String, pins: ZenTaoDocPins) async -> Outcome<Void> { .success(()) }
        func watchLibs(accountId: String) -> AsyncStream<[ZenTaoDocLib]> { AsyncStream { $0.finish() } }
        func watchDocs(accountId: String, libId: String) -> AsyncStream<[ZenTaoDocSummary]> { AsyncStream { $0.finish() } }
        func watchDoc(accountId: String, docId: String) -> AsyncStream<ZenTaoDoc?> { AsyncStream { $0.finish() } }
        func refreshLibs(account: Account) async -> Outcome<Void> { .success(()) }
        func refreshDocs(account: Account, libId: String) async -> Outcome<Void> { .success(()) }
        func refreshDoc(account: Account, docId: String) async -> Outcome<Void> { .success(()) }
        func watchHistory(accountId: String, docId: String) -> AsyncStream<[ZenTaoDocAction]> { AsyncStream { $0.finish() } }
        func refreshHistory(account: Account, docId: String) async -> Outcome<Void> { .success(()) }
        func fetchImage(account: Account, url: String) async -> Data? { nil }
        func readFile(account: Account, file: TicketAttachment) async -> Outcome<Data> { .failure(.notFound("x")) }
        func saveFile(account: Account, file: TicketAttachment) async -> Outcome<String> { .failure(.notFound("x")) }
    }

    private let exportAccount = Account(id: "a1", workspaceId: "w1", providerType: .zentao, handle: "thanh", baseUrl: "https://zt.example.com")
    private let exportDoc = ZenTaoDoc(id: "50", title: "Swap APIs", libId: "89", html: "<h2>Auth</h2><p><img src=\"/file-read-7.png\"></p>")

    func testMarkdownIsSavedAsTitleMd() async {
        let repo = ExportRepository()
        let res = await ZentaoModuleData.exportDoc(repo)(exportAccount, exportDoc, .markdown)
        XCTAssertNotNil(res.value)
        XCTAssertEqual(repo.savedText.first?.0, "Swap APIs.md")
        XCTAssertTrue(repo.savedText.first?.1.hasPrefix("# Swap APIs\n\n## Auth") == true)
        XCTAssertTrue(repo.savedText.first?.1.contains("![](/file-read-7.png)") == true)
    }

    func testHtmlIsAStandalonePageWhoseSiteRelativeLinksResolve() async {
        let repo = ExportRepository()
        _ = await ExportZenTaoDoc(repo)(exportAccount, exportDoc, .html)
        let html = repo.savedText.first?.1 ?? ""
        XCTAssertEqual(repo.savedText.first?.0, "Swap APIs.html")
        XCTAssertTrue(html.contains("<title>Swap APIs</title>"))
        XCTAssertTrue(html.contains("src=\"https://zt.example.com/file-read-7.png\""))
    }

    func testTheBackupIsZenTaosRecordAndAnUnreadableOneSavesNothing() async {
        let repo = ExportRepository()
        _ = await ExportZenTaoDoc(repo)(exportAccount, exportDoc, .backup)
        XCTAssertEqual(repo.savedText.first?.0, "Swap APIs.json")
        XCTAssertEqual(repo.savedText.first?.1, "{\"id\": 50}")
        let failing = ExportRepository()
        failing.backup = .failure(.notFound("not cached"))
        let res = await ExportZenTaoDoc(failing)(exportAccount, exportDoc, .backup)
        XCTAssertNotNil(res.failure)
        XCTAssertTrue(failing.savedText.isEmpty)
    }

    func testTheMarkdownConverterHandlesTheEditorsBlocks() {
        let html = "<h1>T</h1><p>a <strong>b</strong> <em>c</em> <a href=\"https://x\">l</a> <code>k</code></p>"
            + "<ul><li>one<ul><li>deep</li></ul></li><li>two</li></ul><ol><li>x</li></ol><blockquote><p>q</p></blockquote>"
            + "<pre><code class=\"language-swift\">let a = 1</code></pre>"
            + "<table><thead><tr><th>N</th><th>V</th></tr></thead><tbody><tr><td>a</td><td>1</td></tr></tbody></table>"
        let md = ZenTaoDocMarkdown.render(ZenTaoDoc(id: "1", title: "Doc", libId: "1", html: html))
        XCTAssertTrue(md.hasPrefix("# Doc\n\n# T\n\na **b** *c* [l](https://x) `k`"))
        XCTAssertTrue(md.contains("- one\n  - deep\n- two"))
        XCTAssertTrue(md.contains("1. x"))
        XCTAssertTrue(md.contains("> q"))
        XCTAssertTrue(md.contains("```swift\nlet a = 1\n```"))
        XCTAssertTrue(md.contains("| N | V |\n| --- | --- |\n| a | 1 |"))
        XCTAssertEqual(ZenTaoDocMarkdown.render(ZenTaoDoc(id: "1", title: "Empty", libId: "1")), "# Empty")
        XCTAssertEqual(zenTaoDocMarkdownFallback(ZenTaoDoc(id: "1", title: "F", libId: "1", html: "<p>x</p>")), "# F\n\nx")
    }
}
