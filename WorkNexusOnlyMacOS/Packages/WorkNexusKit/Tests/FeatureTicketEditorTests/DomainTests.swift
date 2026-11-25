import CoreDomain
import XCTest
@testable import FeatureTicketEditor

/// Ports of the pure parts of lib/features/ticket_editor (validate_ticket_draft, zentao_choices, route / label helpers).
final class DomainTests: XCTestCase {
    func testBugNeedsTitleBuildAndProduct() {
        var d = BugDraft(product: "0")
        d.openedBuilds = []
        XCTAssertEqual(ValidateBugDraft()(d), [.title, .openedBuilds, .product])
        d.title = "  boom "; d.openedBuilds = ["trunk"]; d.product = "3"
        XCTAssertTrue(ValidateBugDraft()(d).isEmpty)
        d.title = "   "
        XCTAssertEqual(ValidateBugDraft()(d), [.title])
    }

    func testTaskNeedsNameTypeExecutionAndSaneDates() {
        var d = TaskDraft(execution: "0")
        d.type = ""
        XCTAssertEqual(ValidateTaskDraft()(d), [.name, .type, .execution])
        d = TaskDraft(execution: "5"); d.name = "Do it"
        XCTAssertTrue(ValidateTaskDraft()(d).isEmpty)
        d.estStarted = "2026-11-10"; d.deadline = "2026-11-09"
        XCTAssertEqual(ValidateTaskDraft()(d), [.deadline])
        d.deadline = "2026-11-10"
        XCTAssertTrue(ValidateTaskDraft()(d).isEmpty)
        d.deadline = ""
        XCTAssertTrue(ValidateTaskDraft()(d).isEmpty)
    }

    func testWithValueKeepsCustomisedServerValues() {
        XCTAssertEqual(ZenTaoChoices.withValue(ZenTaoChoices.bugTypes, "codeerror").count, 9)
        let extended = ZenTaoChoices.withValue(ZenTaoChoices.bugTypes, "weird")
        XCTAssertEqual(extended.last, FormOption(value: "weird", label: "weird"))
        XCTAssertEqual(ZenTaoChoices.withValue(ZenTaoChoices.bugTypes, "").count, 9)
        XCTAssertEqual(ZenTaoChoices.taskTypes.map(\.value).first, "design")
        XCTAssertEqual(ZenTaoChoices.titleColors.count, 6)
    }

    func testBugScopeResetsDependentPicks() {
        var d = BugDraft(product: "7"); d.module = "3"; d.story = "9"; d.task = "4"; d.execution = "5"
        let byProduct = EditorRules.bugScope(d, product: "8", project: nil, execution: nil)
        XCTAssertEqual([byProduct.product, byProduct.module, byProduct.story, byProduct.task, byProduct.execution], ["8", "0", "0", "0", "5"])
        let byExecution = EditorRules.bugScope(d, product: nil, project: nil, execution: "6")
        XCTAssertEqual([byExecution.product, byExecution.module, byExecution.execution, byExecution.story], ["7", "3", "6", "0"])
    }

    func testMergeOptionsKeepsProductsUsersAndExecutions() {
        var fetched = BugFormOptions(); fetched.modules = [FormOption(value: "1", label: "m")]
        let merged = EditorRules.mergeBugOptions(current: FakeEditor.bugOptions, fetched: fetched)
        XCTAssertEqual(merged.products.count, 2)
        XCTAssertEqual(merged.users.count, 2)
        XCTAssertEqual(merged.modules.count, 1)
        XCTAssertTrue(merged.builds.isEmpty)
        let task = EditorRules.mergeTaskOptions(current: FakeEditor.taskOptions, fetched: TaskFormOptions())
        XCTAssertEqual(task.executions.count, 2)
        XCTAssertTrue(task.users.isEmpty)
    }

    func testPrunedBuildsDropsWhatTheNewChoicesLack() {
        var d = BugDraft(product: "7"); d.openedBuilds = ["trunk", "b1", "gone"]
        var o = BugFormOptions(); o.builds = [FormOption(value: "b1", label: "Build 1")]
        XCTAssertEqual(EditorRules.prunedBuilds(d, options: o), ["trunk", "b1"])
    }

    func testTaskExecutionResetsModuleAndStory() {
        var d = TaskDraft(execution: "5"); d.module = "2"; d.story = "3"
        let moved = EditorRules.taskExecution(d, execution: "6")
        XCTAssertEqual([moved.execution, moved.module, moved.story], ["6", "0", "0"])
    }

    func testKeptDraftsLeaveAddedFilesOut() {
        var d = BugDraft(product: "7"); d.newFiles = [DraftFile(name: "a.mp4", bytes: Data([1]))]
        let kept = EditorRules.keptBug(id: "d1", accountId: "a", uid: "u", now: Date(timeIntervalSince1970: 5), draft: d)
        guard case .bug(let inner) = kept.content else { return XCTFail() }
        XCTAssertTrue(inner.newFiles.isEmpty)
        XCTAssertEqual(kept.updatedAt, Date(timeIntervalSince1970: 5))
    }

    func testFormValueFormats() {
        XCTAssertEqual(FormValueFormat.hoursText(0), "")
        XCTAssertEqual(FormValueFormat.hoursText(3), "3")
        XCTAssertEqual(FormValueFormat.hoursText(2.5), "2.5")
        XCTAssertEqual(FormValueFormat.parseHours("1.5"), 1.5)
        XCTAssertEqual(FormValueFormat.parseHours("."), 0)
        let day = FormValueFormat.date("2026-11-16")
        XCTAssertNotNil(day)
        XCTAssertEqual(FormValueFormat.dateText(day), "2026-11-16")
        XCTAssertNil(FormValueFormat.date(""))
        XCTAssertEqual(FormValueFormat.dateText(nil), "")
        XCTAssertFalse(FormValueFormat.newFormUid().isEmpty)
        XCTAssertEqual(FormValueFormat.shortDraftTitle(String(repeating: "x", count: 60)), String(repeating: "x", count: 40) + "…")
        XCTAssertEqual(FormValueFormat.shortDraftTitle(" short "), "short")
    }

    func testLaunchHelpers() {
        let draft = ZenTaoSavedDraft(id: "d1", accountId: "a", uid: "u", updatedAt: Date(), content: .task({ var t = TaskDraft(execution: "5"); t.name = "x"; return t }()))
        XCTAssertEqual(TicketEditorLaunch.resuming(draft), .newTask(accountId: "a", executionId: "5", draftId: "d1"))
        XCTAssertEqual(TicketEditorLaunch.resuming(draft).draftId, "d1")
        XCTAssertTrue(TicketEditorLaunch.newBug(accountId: "a").isBug)
        XCTAssertFalse(TicketEditorLaunch.editTask(accountId: "a", taskId: "1").isNew)
        XCTAssertEqual(TicketEditorLaunch.zenTaoId(from: "zt-x-1a:bug:6492"), "6492")
        XCTAssertEqual(TicketEditorLaunch.zenTaoId(from: "6492"), "6492")
    }

    func testNavRoutesBecomeLaunches() {
        XCTAssertEqual(TicketEditorView.launch(for: .newBug(accountId: "a", productId: nil)), .newBug(accountId: "a", productId: "0"))
        XCTAssertEqual(TicketEditorView.launch(for: .newTask(accountId: "a", executionId: "5")), .newTask(accountId: "a", executionId: "5"))
        XCTAssertEqual(TicketEditorView.launch(for: .newTask(accountId: "a", executionId: "5", fromBug: "9")),
                       .newTask(accountId: "a", executionId: "5", fromBug: "9"))
        XCTAssertEqual(TicketEditorView.launch(for: .editBug(accountId: "a", ticketId: "a:bug:12")), .editBug(accountId: "a", bugId: "12"))
        XCTAssertEqual(TicketEditorView.launch(for: .editTask(accountId: "a", ticketId: "a:task:13")), .editTask(accountId: "a", taskId: "13"))
    }

    func testNumericInputKeepsDigitsAndOneDot() {
        XCTAssertEqual(EditorTextInput.hoursOnly("1a2.3.4"), "12.34")
        XCTAssertEqual(EditorTextInput.hoursOnly("abc"), "")
    }
}
