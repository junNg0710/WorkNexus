import CoreDomain
import CoreTools
import XCTest
@testable import FeatureTicketEditor

/// Controllers over a fake `ZenTaoTicketEditor` and an in-memory draft repository (mocks at the interface boundary).
@MainActor
final class ControllerTests: XCTestCase {
    private func bugController(_ editor: FakeEditor, drafts: FakeDrafts? = FakeDrafts(),
                               launch: TicketEditorLaunch = .newBug(accountId: "a")) -> BugEditorController {
        BugEditorController(launch: launch, gateway: TicketEditorGateway(editor: editor, drafts: drafts, members: FakeMembers()),
                            autosaveDelay: .milliseconds(20))
    }
    private func taskController(_ editor: FakeEditor, drafts: FakeDrafts? = FakeDrafts(),
                                launch: TicketEditorLaunch = .newTask(accountId: "a", executionId: "5")) -> TaskEditorController {
        TaskEditorController(launch: launch, gateway: TicketEditorGateway(editor: editor, drafts: drafts, members: FakeMembers()),
                             autosaveDelay: .milliseconds(20))
    }
    private func eventually(_ cond: @autoclosure () -> Bool, _ message: String = "") async {
        for _ in 0..<100 where !cond() { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(cond(), message)
    }

    // MARK: Bug

    func testNewBugLoadsFormAndStartsADraft() async {
        let c = bugController(FakeEditor())
        XCTAssertTrue(c.isLoading)
        await c.load()
        XCTAssertFalse(c.isLoading)
        XCTAssertEqual(c.state?.draft.product, "7")
        XCTAssertNotNil(c.state?.draftId)
        XCTAssertNil(c.state?.draftSavedAt)
        XCTAssertNotNil(c.steps)
        await c.close()
    }

    func testANewBugOrTaskMadeFromAChatMessageStartsWithItsTitleAndBody() async {
        let prefill = TicketEditorPrefill(title: "Login fails", bodyHtml: "<p>tap login</p>")
        let gateway = TicketEditorGateway(editor: FakeEditor(), drafts: FakeDrafts(), members: FakeMembers())
        let bug = BugEditorController(launch: .newBug(accountId: "a"), gateway: gateway, prefill: prefill)
        await bug.load()
        XCTAssertEqual(bug.state?.draft.title, "Login fails")
        XCTAssertEqual(bug.state?.draft.steps, "<p>tap login</p>")
        XCTAssertEqual(bug.steps?.html, "<p>tap login</p>", "the editor shows it")
        XCTAssertEqual(bug.state?.draft.product, "7", "the rest is still ZenTao's form")
        await bug.close()
        let task = TaskEditorController(launch: .newTask(accountId: "a", executionId: "5"), gateway: gateway, prefill: prefill)
        await task.load()
        XCTAssertEqual(task.state?.draft.name, "Login fails")
        XCTAssertEqual(task.state?.draft.desc, "<p>tap login</p>")
        await task.close()
        // An existing bug is never overwritten.
        let edit = BugEditorController(launch: .editBug(accountId: "a", bugId: "42"), gateway: gateway, prefill: prefill)
        await edit.load()
        XCTAssertNotEqual(edit.state?.draft.title, "Login fails")
        await edit.close()
    }

    func testEditBugHasNoDraft() async {
        let c = bugController(FakeEditor(), launch: .editBug(accountId: "a", bugId: "42"))
        await c.load()
        XCTAssertEqual(c.state?.draft.id, "42")
        XCTAssertNil(c.state?.draftId)
        await c.close()
    }

    func testMissingEditorShowsAnErrorStateNotACrash() async {
        let c = BugEditorController(launch: .newBug(accountId: "a"), gateway: TicketEditorGateway(editor: nil))
        await c.load()
        XCTAssertNil(c.state)
        XCTAssertFalse(c.isLoading)
        XCTAssertEqual(c.loadFailure, TicketEditorGateway.unavailable)
        let t = TaskEditorController(launch: .newTask(accountId: "a"), gateway: TicketEditorGateway(editor: nil))
        await t.load()
        XCTAssertNotNil(t.loadFailure)
        let saved = await c.save()
        XCTAssertNil(saved)
    }

    func testLoadFailureIsReported() async {
        let editor = FakeEditor(); editor.formFailure = .network("offline")
        let c = bugController(editor)
        await c.load()
        XCTAssertEqual(c.loadFailure, .network("offline"))
    }

    func testEditKeepsADraftOncePaused() async {
        let drafts = FakeDrafts()
        let c = bugController(FakeEditor(), drafts: drafts)
        await c.load()
        c.edit { $0.title = "Feed freezes" }
        await eventually(c.state?.draftSavedAt != nil, "draft was not kept")
        XCTAssertEqual(drafts.all.count, 1)
        guard case .bug(let kept) = drafts.all.first?.content else { return XCTFail() }
        XCTAssertEqual(kept.title, "Feed freezes")
        await c.close()
    }

    func testUntouchedFormKeepsNothing() async {
        let drafts = FakeDrafts()
        let c = bugController(FakeEditor(), drafts: drafts)
        await c.load()
        c.edit { _ in }
        await c.close()
        XCTAssertTrue(drafts.all.isEmpty)
    }

    func testCloseFlushesAChangeStillWaiting() async {
        let drafts = FakeDrafts()
        let c = BugEditorController(launch: .newBug(accountId: "a"), gateway: TicketEditorGateway(editor: FakeEditor(), drafts: drafts),
                                    autosaveDelay: .seconds(30))
        await c.load()
        c.edit { $0.title = "Typed last" }
        XCTAssertTrue(drafts.all.isEmpty)
        await c.close()
        XCTAssertEqual(drafts.all.count, 1)
    }

    func testSaveRefusesAnIncompleteBugAndMarksTheFields() async {
        let editor = FakeEditor()
        let c = bugController(editor)
        await c.load()
        let id = await c.save()
        XCTAssertNil(id)
        XCTAssertEqual(c.state?.missing, [.title])
        XCTAssertTrue(editor.savedBugs.isEmpty)
        c.edit { $0.title = "now fine" }
        XCTAssertEqual(c.state?.missing, [])
        await c.close()
    }

    func testSaveSendsTheDraftAndDiscardsTheKeptOne() async {
        let editor = FakeEditor(); let drafts = FakeDrafts()
        let c = bugController(editor, drafts: drafts)
        await c.load()
        c.edit { $0.title = "Crash" }
        await eventually(!drafts.all.isEmpty)
        let id = await c.save()
        XCTAssertEqual(id, "zt-a:bug:99")
        XCTAssertEqual(editor.savedBugs.map(\.title), ["Crash"])
        XCTAssertNil(c.state?.draftId)
        XCTAssertTrue(drafts.all.isEmpty)
        XCTAssertEqual(c.state?.saving, false)
        await c.close()
        XCTAssertTrue(drafts.all.isEmpty, "a saved bug must not come back as a draft")
    }

    func testSaveFailureStaysOpenWithTheReason() async {
        let editor = FakeEditor(); editor.saveResult = .failure(.network("refused"))
        let c = bugController(editor)
        await c.load()
        c.edit { $0.title = "x" }
        let id = await c.save()
        XCTAssertNil(id)
        XCTAssertEqual(c.state?.failure, .network("refused"))
        XCTAssertEqual(c.state?.saving, false)
        await c.close()
    }

    func testChangeScopeReloadsChoicesAndPrunesBuilds() async {
        let editor = FakeEditor()
        var fetched = BugFormOptions()
        fetched.builds = [FormOption(value: "b2", label: "Build 2")]
        fetched.modules = [FormOption(value: "9", label: "/New")]
        editor.fetchedBugOptions = fetched
        let c = bugController(editor)
        await c.load()
        c.edit { $0.openedBuilds = ["trunk", "b1", "b2"]; $0.module = "1" }
        await c.changeScope(product: "8")
        XCTAssertEqual(c.state?.draft.product, "8")
        XCTAssertEqual(c.state?.draft.module, "0")
        XCTAssertEqual(c.state?.draft.openedBuilds, ["trunk", "b2"])
        XCTAssertEqual(c.state?.form.options.modules.map(\.value), ["9"])
        XCTAssertEqual(c.state?.form.options.products.count, 2, "products are kept when ZenTao sends none")
        XCTAssertTrue(editor.calls.contains("bugOptions:8:0:0"))
        await c.close()
    }

    func testChangeScopeKeepsTheDraftWhenOptionsFail() async {
        let c = bugController(FakeEditor())
        await c.load()
        await c.changeScope(execution: "6")
        XCTAssertEqual(c.state?.draft.execution, "6")
        XCTAssertEqual(c.state?.form.options.builds.count, 3)
        await c.close()
    }

    func testReopeningADraftRestoresItsFormAndSession() async {
        var written = BugDraft(product: "8"); written.title = "Half written"; written.project = "3"
        let kept = ZenTaoSavedDraft(id: "d1", accountId: "a", uid: "session-1", updatedAt: Date(timeIntervalSince1970: 100), content: .bug(written))
        let editor = FakeEditor()
        var fetched = BugFormOptions(); fetched.modules = [FormOption(value: "2", label: "/Two")]
        editor.fetchedBugOptions = fetched
        let c = bugController(editor, drafts: FakeDrafts([kept]), launch: .newBug(accountId: "a", productId: "8", draftId: "d1"))
        await c.load()
        XCTAssertEqual(c.state?.draft.title, "Half written")
        XCTAssertEqual(c.state?.uid, "session-1")
        XCTAssertEqual(c.state?.draftId, "d1")
        XCTAssertEqual(c.state?.draftSavedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(c.state?.form.options.modules.map(\.value), ["2"])
        XCTAssertTrue(editor.calls.contains("newBugForm:8"))
        await c.close()
    }

    func testDiscardDraftDeletesItAndReportsFailure() async {
        let drafts = FakeDrafts()
        let c = bugController(FakeEditor(), drafts: drafts)
        await c.load()
        c.edit { $0.title = "bye" }
        await eventually(!drafts.all.isEmpty)
        drafts.deleteFailure = .storage("locked")
        let first = await c.discardDraft()
        XCTAssertFalse(first)
        XCTAssertEqual(c.state?.failure, .storage("locked"))
        drafts.deleteFailure = nil
        let second = await c.discardDraft()
        XCTAssertTrue(second)
        XCTAssertNil(c.state?.draftId)
        XCTAssertNil(c.state?.draftSavedAt)
        XCTAssertTrue(drafts.all.isEmpty)
        await c.close()
    }

    func testUploadedImageGoesUnderTheFormSession() async {
        let c = bugController(FakeEditor())
        await c.load()
        let url = await c.uploadImage(Data([1, 2]), "p.png")
        XCTAssertEqual(url, "/file-read-1.png")
        await c.close()
    }

    // MARK: Task

    func testNewTaskAndSubtaskLaunch() async {
        let editor = FakeEditor()
        let sub = taskController(editor, launch: .newTask(accountId: "a", executionId: "5", parentId: "40"))
        await sub.load()
        XCTAssertEqual(editor.newTaskParents, ["40"])
        XCTAssertEqual(sub.state?.draft.parent, "40")
        sub.edit { $0.name = "Subtask" }
        let id = await sub.save()
        XCTAssertNotNil(id)
        XCTAssertEqual(editor.savedTasks.first?.parent, "40", "a subtask is saved with its parent (batch create)")
        await sub.close()
    }

    func testTaskSaveValidates() async {
        let editor = FakeEditor()
        let c = taskController(editor)
        await c.load()
        let id = await c.save()
        XCTAssertNil(id)
        XCTAssertEqual(c.state?.missing, [.name])
        c.edit { $0.name = "Task"; $0.estStarted = "2026-11-10"; $0.deadline = "2026-11-01" }
        let id2 = await c.save()
        XCTAssertNil(id2)
        XCTAssertEqual(c.state?.missing, [.deadline])
        XCTAssertTrue(editor.savedTasks.isEmpty)
        await c.close()
    }

    func testChangeExecutionMergesOptionsAndFallsBackToTeamMembers() async {
        let editor = FakeEditor()
        var fetched = TaskFormOptions(); fetched.modules = [FormOption(value: "4", label: "/M")]
        editor.fetchedTaskOptions = fetched
        let c = taskController(editor)
        await c.load()
        c.edit { $0.module = "2"; $0.story = "3" }
        await c.changeExecution("6")
        XCTAssertEqual(c.state?.draft.execution, "6")
        XCTAssertEqual(c.state?.draft.module, "0")
        XCTAssertEqual(c.state?.form.options.modules.map(\.value), ["4"])
        XCTAssertEqual(c.state?.form.options.executions.count, 2)
        XCTAssertEqual(c.state?.form.options.users.map(\.value), ["ryan"], "no assignees in the form: the execution's team")
        await c.close()
    }

    func testTaskDraftIsKeptAndRestored() async {
        let drafts = FakeDrafts()
        let c = taskController(FakeEditor(), drafts: drafts)
        await c.load()
        c.edit { $0.name = "Write docs" }
        await eventually(c.state?.draftSavedAt != nil)
        guard let kept = drafts.all.first, case .task = kept.content else { return XCTFail("no task draft") }
        await c.close()
        let again = taskController(FakeEditor(), drafts: drafts, launch: TicketEditorLaunch.resuming(kept))
        await again.load()
        XCTAssertEqual(again.state?.draft.name, "Write docs")
        XCTAssertEqual(again.state?.draftId, kept.id)
        await again.close()
    }

    func testEditTaskHasNoDraftAndShowsProgress() async {
        let c = taskController(FakeEditor(), launch: .editTask(accountId: "a", taskId: "77"))
        await c.load()
        XCTAssertEqual(c.state?.draft.id, "77")
        XCTAssertNil(c.state?.draftId)
        await c.close()
    }

    // MARK: Autosave

    func testAutosaveKeepsOnlyTheLastChange() async {
        let drafts = FakeDrafts()
        let auto = DraftAutosave(drafts, delay: .milliseconds(30))
        for i in 1...3 {
            auto.schedule(EditorRules.keptBug(id: "d", accountId: "a", uid: "u", now: Date(timeIntervalSince1970: Double(i)), draft: { var b = BugDraft(product: "7"); b.title = "v\(i)"; return b }()))
        }
        await eventually(drafts.saves == 1)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(drafts.saves, 1)
        XCTAssertEqual(drafts.all.first?.title, "v3")
    }

    func testAutosaveCancelDropsThePendingChange() async {
        let drafts = FakeDrafts()
        let auto = DraftAutosave(drafts, delay: .milliseconds(20))
        auto.schedule(EditorRules.keptBug(id: "d", accountId: "a", uid: "u", now: Date(), draft: BugDraft(product: "7")))
        auto.cancel()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(drafts.saves, 0)
    }
}

/// The multi-select's ticks: in the options' order, keeping picks the list does not have.
final class OptionMultiSelectLogicTests: XCTestCase {
    func testTickingKeepsTheOptionsOrderAndUnknownPicks() {
        let options = [FormOption(value: "1", label: "A"), FormOption(value: "2", label: "B"), FormOption(value: "3", label: "C")]
        XCTAssertEqual(OptionMultiSelect.toggled(["3"], "1", options: options), ["1", "3"])
        XCTAssertEqual(OptionMultiSelect.toggled(["1", "3"], "3", options: options), ["1"])
        XCTAssertEqual(OptionMultiSelect.toggled(["99"], "2", options: options), ["2", "99"])
        XCTAssertEqual(OptionMultiSelect.toggled([], "2", options: options), ["2"])
    }
}
