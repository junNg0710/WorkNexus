import CoreDomain
import XCTest
@testable import ToolZenTao

/// Ported from: test/data/zentao_ticket_forms_test.dart
final class ZenTaoTicketFormsTests: XCTestCase {
    /// A forms loader over a stub whose handler answers with a JSON value (tokens are answered for it).
    private func makeForms(_ handler: @escaping (StubRequest) -> Any) -> (ZenTaoTicketForms, StubServer) {
        let server = StubServer { req in
            req.path.hasSuffix("/tokens") ? .json(["token": "t"]) : .json(handler(req))
        }
        return (ZenTaoTicketForms(client: makeClient(server, base: "https://z.example.com/zentao")), server)
    }

    private func sent(_ server: StubServer, _ path: String) throws -> StubRequest {
        try XCTUnwrap(server.requests.last { $0.path.contains(path) })
    }

    // MARK: Parsing

    func testOptionsReadMapsAndPhpListsLeavingOutTheNones() {
        XCTAssertEqual(zentaoOptions(["0": "/", "3": "/Login", "": ""] as JSON), [FormOption(value: "3", label: "/Login")])
        XCTAssertEqual(zentaoOptions(["", "Trunk"] as [Any]), [FormOption(value: "1", label: "Trunk")])
        // Order of an ordered (parsed) map is kept.
        XCTAssertEqual(zentaoOptions(ordered(["b": "B", "a": "A"])).map(\.value), ["b", "a"])
        XCTAssertEqual(zentaoOptions(["closed": "x", "ok": "&lt;Fine&gt;"] as JSON), [FormOption(value: "ok", label: "<Fine>")])
    }

    func testASaveReplyGivesTheIdOrTheRefusedFields() throws {
        XCTAssertEqual(try zentaoSaveResult(["result": "success", "id": 42] as JSON), "42")
        // 18.x wraps an edit's reply like a page.
        XCTAssertEqual(try zentaoSaveResult(wrapped(["locate": "https://z/zentao/bug-view-7.html"])), "7")
        XCTAssertThrowsError(try zentaoSaveResult(["result": "fail", "message": ["openedBuild[]": ["『Affected Build』should not be blank."]]] as JSON)) {
            XCTAssertEqual($0 as? Failure, .validation("『Affected Build』should not be blank.", fields: ["openedBuild": "『Affected Build』should not be blank."]))
        }
        XCTAssertThrowsError(try zentaoSaveResult("<html>SQL error</html>")) {
            guard case .validation = $0 as? Failure else { return XCTFail("expected a validation failure") }
        }
    }

    func testStoryAndTaskLabelsReadAsHashIdName() {
        let people: Set<String> = ["Dyno-VN-Flutter"]
        XCTAssertEqual(zentaoLinkLabel("11421:Dyno-VN-Flutter:[Mobile] enhance", people: people), "#11421 [Mobile] enhance")
        XCTAssertEqual(zentaoLinkLabel("[C] 11983:Dyno-VN-Flutter:mobile", people: people), "[C] #11983 mobile")
        // Not finished: a colon in the name stays.
        XCTAssertEqual(zentaoLinkLabel("7313:Fix: crash", people: people), "#7313 Fix: crash")
        XCTAssertEqual(zentaoLinkLabel("Share post"), "Share post")
    }

    func testPickerItemsInThePageAreReadByValueNotPosition() {
        XCTAssertEqual(zentaoOptions([["value": "7", "text": "Login"] as JSON] as [Any]), [FormOption(value: "7", label: "Login")])
        XCTAssertEqual(zentaoPickerOptions([
            ["value": "18", "label": "Share livestream"] as JSON,
            ["value": "76", "title": "Gift"] as JSON,
            // 20+ story with a grade: `text` is a badge as HTML.
            ["text": ["html": "<span class='label'>SR</span> Share post"] as JSON, "hint": "Share post", "value": 173, "keys": "Share post"] as JSON,
        ] as [Any]), [
            FormOption(value: "18", label: "Share livestream"),
            FormOption(value: "76", label: "Gift"),
            FormOption(value: "173", label: "Share post"),
        ])
    }

    func testClassicPayloadUnwrapsTheDoubleEncodedData() {
        XCTAssertEqual(classicPayload(wrapped(["bug": ["id": 1] as JSON]))?["bug"].flatMap(asMap)?["id"] as? Int, 1)
        XCTAssertNotNil(classicPayload(#"{"status":"success","data":"{\"a\":1}"}"#))
        XCTAssertNil(classicPayload("<html>login</html>"))
        XCTAssertNotNil(classicData(#"[{"value":"1","text":"a"}]"#) as? [Any])
        XCTAssertNil(classicData("<select></select>"))
    }

    func testTextHelpers() {
        XCTAssertEqual(zentaoId(nil), "0")
        XCTAssertEqual(zentaoId(" 7 "), "7")
        XCTAssertEqual(zentaoDate("0000-00-00"), "")
        XCTAssertEqual(zentaoDate("2026-10-13 10:00:00"), "2026-10-13")
        XCTAssertEqual(zentaoCsv("a, b,,c"), ["a", "b", "c"])
        XCTAssertEqual(zentaoCsv(["x", " "]), ["x"])
        XCTAssertEqual(zentaoText("A &amp; B"), "A & B")
        XCTAssertEqual(zentaoNumber("2.5"), 2.5)
        XCTAssertEqual(zentaoIntOr("x", 3), 3)
    }

    // MARK: Bugs

    func testANewBugOn18ReadsItsFlatDefaultsAndChoices() async throws {
        let (forms, _) = makeForms { _ in
            wrapped(["bugTitle": "", "products": ["4": "VN_Socialfi"], "moduleOptionMenu": ["0": "/", "12": "/Feed"],
                     "builds": ["trunk": "Trunk"], "productMembers": ["thanh": "Thanh", "closed": "Closed"] as JSON,
                     "steps": "&lt;p&gt;[Steps]&lt;/p&gt;", "severity": "2", "type": "codeerror"] as JSON)
        }
        let form = try await forms.newBug("4")
        XCTAssertEqual(form.draft.severity, 2)
        XCTAssertEqual(form.draft.steps, "<p>[Steps]</p>")
        XCTAssertEqual(form.draft.openedBuilds, ["trunk"])
        XCTAssertEqual(form.options.modules.map(\.label), ["/Feed"])
        XCTAssertEqual(form.options.users, [FormOption(value: "thanh", label: "Thanh")])
        XCTAssertEqual(form.kept[zentaoLegacyKey], "1")
    }

    func testEditingAResolvedBugOn18SendsEveryFieldBack() async throws {
        let (forms, server) = makeForms { req in
            if req.path.contains("bug-edit-7"), req.method == "GET" {
                return wrapped(["bug": ["id": 7, "product": 4, "title": "A &amp; B", "openedBuild": "trunk,12", "os": "android,ios",
                                        "status": "resolved", "resolution": "fixed", "resolvedBuild": "trunk", "linkBug": "3,5",
                                        "lastEditedDate": "2026-09-01 10:00:00", "deadline": "0000-00-00"] as JSON,
                                "products": ["4": "VN_Socialfi"]] as JSON)
            }
            if req.path.contains("bug-create-4") { return wrapped(["builds": ["trunk": "Trunk", "12": "v1.2"]] as JSON) }
            return wrapped(["locate": "x"])
        }
        let form = try await forms.editBug("7")
        XCTAssertEqual(form.draft.title, "A & B")
        XCTAssertEqual(form.draft.openedBuilds, ["trunk", "12"])
        XCTAssertEqual(form.options.builds.count, 2)

        var edited = form.draft
        edited.title = "A & C"
        let id = try await forms.saveBug(form, edited, uid: "u1")

        XCTAssertEqual(id, "7")
        let req = try sent(server, "bug-edit-7")
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.field("title"), "A & C")
        XCTAssertEqual(req.form["os[]"], ["android", "ios"])
        XCTAssertEqual(req.field("status"), "resolved")
        XCTAssertEqual(req.field("resolution"), "fixed")
        XCTAssertEqual(req.field("lastEditedDate"), "2026-09-01 10:00:00")
        // 18.x names related bugs linkBug, and an empty date is left out.
        XCTAssertEqual(req.form["linkBug[]"], ["3", "5"])
        XCTAssertNil(req.form["relatedBug[]"])
        XCTAssertNil(req.form["deadline"])
    }

    func testRemovedAttachmentsAreSentAsDeleteFiles() async throws {
        let (forms, server) = makeForms { req in
            if req.method == "GET" {
                return wrapped(["bug": ["id": 7, "product": 4, "title": "x", "openedBuild": "trunk",
                                        "files": ["10": ["id": 10, "title": "a.png", "extension": "png"] as JSON,
                                                  "11": ["id": 11, "title": "b.png", "extension": "png"] as JSON] as JSON] as JSON,
                                "openedBuilds": ["trunk": "Trunk"]] as JSON)
            }
            return ["result": "success"] as JSON
        }
        let form = try await forms.editBug("7")
        XCTAssertEqual(form.draft.files.map(\.id), ["10", "11"])
        var edited = form.draft
        edited.files.removeAll { $0.id == "10" }
        _ = try await forms.saveBug(form, edited, uid: "u")
        XCTAssertEqual(try sent(server, "bug-edit-7").form["deleteFiles[]"], ["10"])
    }

    func testANewBugLoadsTheStoriesAndTasksToLinkByAjax() async throws {
        let (forms, server) = makeForms { req in
            if req.path.contains("story-ajaxGetProductStories-5-") {
                return [["value": "", "text": ""] as JSON, ["value": "88", "text": "88:Share livestream"] as JSON] as [Any]
            }
            if req.path.contains("task-ajaxGetExecutionTasks-31") { return [["value": "10007", "text": "10007:Build share sheet"] as JSON] as [Any] }
            return wrapped(["bug": ["productID": 5, "executionID": 31, "taskID": 10007] as JSON] as JSON)
        }
        let form = try await forms.newBug("0", executionId: "31", taskId: "10007")
        XCTAssertEqual(form.options.stories, [FormOption(value: "88", label: "#88 Share livestream")])
        XCTAssertEqual(form.options.tasks, [FormOption(value: "10007", label: "#10007 Build share sheet")])
        XCTAssertEqual(form.draft.task, "10007")
        XCTAssertFalse(server.requests.contains { $0.path.contains("ajaxGetProductStories-0-") })
    }

    func testNoExecutionNoTaskRequestAndAListThatFailsStaysEmpty() async throws {
        let (forms, server) = makeForms { req in
            if req.path.contains("ajaxGetProductStories") { return "<select></select>" }
            return wrapped(["bug": ["productID": 5] as JSON] as JSON)
        }
        let options = try await forms.bugOptions("5")
        XCTAssertTrue(options.stories.isEmpty)
        XCTAssertTrue(options.tasks.isEmpty)
        XCTAssertFalse(server.requests.contains { $0.path.contains("ajaxGetExecutionTasks") })
    }

    func testTaskNamesComeFromTheTaskViewKeepingTheSubtaskMark() async throws {
        let (forms, _) = makeForms { req in
            if req.path.contains("task-ajaxGetExecutionTasks-31") {
                return [["value": 12492, "text": "[C] 12492:Luci-VN-Flutter:share to IM"] as JSON,
                        ["value": 12582, "text": "12582:Sunshine_VN_Golang:Add id: field"] as JSON,
                        ["value": 900, "text": "900:Nobody:Gone"] as JSON] as [Any]
            }
            if req.path.contains("execution-task-31-all-") {
                return ["pager": ["recTotal": 1] as JSON,
                        "tasks": [["id": 12582, "name": "Add id: field", "children": [["id": 12492, "name": "share to IM"] as JSON]] as JSON]] as JSON
            }
            if req.path.contains("ajaxGetProductStories") { return [Any]() }
            return wrapped(["bug": ["productID": 5] as JSON] as JSON)
        }
        let options = try await forms.bugOptions("5", executionId: "31")
        XCTAssertEqual(options.tasks.map(\.label), [
            "[C] #12492 share to IM",
            "#12582 Add id: field",
            // Not in the task view: the ajax label, as best it can be read.
            "#900 Nobody:Gone",
        ])
    }

    func testACopiedBugOn18StartsFromTheCopyZenTaoFillsIn() async throws {
        let (forms, server) = makeForms { _ in
            wrapped(["bugTitle": "Login fails", "title": "VN_Socialfi::Create bug", "productID": "4", "buildID": "trunk,12",
                     "os": "ios", "keywords": "auth", "taskID": "0"] as JSON)
        }
        let form = try await forms.newBug("4", copyOf: "7")
        XCTAssertTrue(server.requests.contains { $0.path.hasSuffix("bug-create-4-0-bugID=7.json") })
        XCTAssertNil(form.draft.id)
        // 18.x's `title` is the page's own; the copy's is `bugTitle`.
        XCTAssertEqual(form.draft.title, "Login fails")
        XCTAssertEqual(form.draft.openedBuilds, ["trunk", "12"])
        XCTAssertEqual(form.draft.os, ["ios"])
        XCTAssertEqual(form.draft.keywords, "auth")
    }

    func testABugFromATaskOpensInTheTasksProductAndStory() async throws {
        let (forms, server) = makeForms { req in
            if req.path.hasSuffix("/tasks/12897") { return ["id": 12897, "project": 7, "execution": 31, "story": 88] as JSON }
            if req.path.hasSuffix("/executions/31") { return ["id": 31, "products": [["id": 4, "name": "VN_Socialfi"] as JSON, ["id": 5, "name": "VN_Shop"] as JSON]] as JSON }
            // The execution spans two products: the story says which.
            if req.path.hasSuffix("/stories/88") { return ["id": 88, "product": 4] as JSON }
            return wrapped(["bug": ["productID": 4, "executionID": 31] as JSON] as JSON)
        }
        let form = try await forms.newBug("0", executionId: "31", taskId: "12897")
        XCTAssertTrue(server.requests.contains { $0.path.hasSuffix("bug-create-4-0-projectID=7,executionID=31,taskID=12897,storyID=88.json") })
        XCTAssertEqual(form.draft.product, "4")
    }

    func testABugFromATaskIsFiledAgainstItsExecutionAndTask() async throws {
        let (forms, server) = makeForms { req in
            if req.path.contains("/api.php/v1/") { return "" }
            return wrapped(["bug": ["productID": 5, "executionID": 31, "taskID": 12, "title": ""] as JSON] as JSON)
        }
        let form = try await forms.newBug("0", executionId: "31", taskId: "12")
        XCTAssertTrue(server.requests.contains { $0.path.hasSuffix("bug-create-0-0-executionID=31,taskID=12.json") })
        // ZenTao picked its current product for '0'.
        XCTAssertEqual(form.draft.product, "5")
        XCTAssertEqual(form.draft.execution, "31")
        XCTAssertEqual(form.draft.task, "12")
        XCTAssertEqual(form.draft.openedBuilds, ["trunk"])
    }

    func testSavingANewBugPostsToBugCreateAndReturnsTheId() async throws {
        let (forms, server) = makeForms { req in
            req.method == "GET" ? wrapped(["bug": ["productID": 4] as JSON] as JSON) : (["result": "success", "id": 321] as JSON)
        }
        let form = try await forms.newBug("4")
        var draft = form.draft
        draft.title = "Crash"
        draft.os = ["ios"]
        draft.newFiles = [DraftFile(name: "log.txt", bytes: Data([1]))]
        let id = try await forms.saveBug(form, draft, uid: "u9")
        XCTAssertEqual(id, "321")
        let req = try sent(server, "bug-create-4-0-.json")
        XCTAssertTrue(req.header("Content-Type")?.hasPrefix("multipart/form-data") == true)
        XCTAssertTrue(req.bodyText.contains("name=\"files[]\"; filename=\"log.txt\""))
        XCTAssertTrue(req.bodyText.contains("name=\"labels[]\""))
        XCTAssertTrue(req.bodyText.contains("name=\"title\"\r\n\r\nCrash"))
    }

    // MARK: Tasks

    func testANewTaskOn18SendsItsAssigneeAsAList() async throws {
        let (forms, server) = makeForms { req in
            req.method == "GET"
                ? wrapped(["moduleOptionMenu": ["0": "/"], "members": ["thanh": "Thanh"], "task": ["type": "devel"] as JSON] as JSON)
                : (["result": "success", "id": 99] as JSON)
        }
        let form = try await forms.newTask("9")
        var draft = form.draft
        draft.name = "mobile"; draft.assignedTo = "thanh"; draft.estimate = 4
        let id = try await forms.saveTask(form, draft, uid: "u2")
        XCTAssertEqual(id, "99")
        let req = try sent(server, "task-create-9")
        XCTAssertEqual(req.form["assignedTo[]"], ["thanh"])
        XCTAssertEqual(req.field("estimate"), "4")
        XCTAssertNil(req.form["keywords"])
    }

    func testEditingATaskSendsItsKeptFieldsAndStatus() async throws {
        let (forms, server) = makeForms { req in
            req.method == "GET"
                ? wrapped(["task": ["id": 5, "execution": 9, "name": "T", "status": "doing", "left": "2.5", "consumed": "1", "parent": 0,
                                    "realStarted": "2026-10-01 09:00:00", "lastEditedDate": "2026-10-02 10:00:00", "closedReason": ""] as JSON,
                           "parentTask": [Any]()] as JSON)
                : (["result": "success"] as JSON)
        }
        let form = try await forms.editTask("5")
        XCTAssertNil(form.kept[zentaoLegacyKey])
        let id = try await forms.saveTask(form, form.draft, uid: "u")
        XCTAssertEqual(id, "5")
        let req = try sent(server, "task-edit-5")
        XCTAssertEqual(req.field("status"), "doing")
        XCTAssertEqual(req.field("left"), "2.5")
        XCTAssertEqual(req.field("consumed"), "1")
        XCTAssertEqual(req.field("realStarted"), "2026-10-01 09:00:00")
        XCTAssertNil(req.form["closedReason"])       // empty kept fields are left out
        XCTAssertNotNil(req.form["keywords"])        // 20+ has the column
    }

    func testANewSubtaskGoesThroughTheBatchFormOneRow() async throws {
        let (forms, server) = makeForms { req in
            req.method == "GET"
                ? wrapped(["moduleOptionMenu": ["0": "/"], "execution": ["id": 31, "name": "Sprint 3"] as JSON] as JSON)
                : (["result": "success", "idList": [130]] as JSON)
        }
        let form = try await forms.newTask("0", parentId: "120")
        XCTAssertEqual(form.draft.execution, "31")
        XCTAssertEqual(form.draft.parent, "120")
        // 18.x lists no parents on its create form; the parent is offered anyway.
        XCTAssertEqual(form.options.parents.first?.value, "120")

        var draft = form.draft
        draft.name = "API"; draft.estimate = 2; draft.desc = "<p>a</p>\n<p>b</p>"
        let id = try await forms.saveTask(form, draft, uid: "u4")
        XCTAssertEqual(id, "130")
        let req = try sent(server, "task-batchCreate-31-0-0-120")
        XCTAssertEqual(req.field("parent[1]"), "120")
        XCTAssertEqual(req.field("name[1]"), "API")
        XCTAssertEqual(req.field("estimate[1]"), "2")
        XCTAssertEqual(req.field("story[1]"), "0")
        XCTAssertEqual(req.field("desc[1]"), "<p>a</p><p>b</p>")
        XCTAssertNil(req.form["estStarted[1]"])
    }

    func testASubtaskZenTaoGivesNoIdForOpensItsParent() async throws {
        let (forms, _) = makeForms { req in
            req.method == "GET" ? wrapped(["moduleOptionMenu": ["0": "/"]] as JSON) : (["result": "success"] as JSON)
        }
        let form = try await forms.newTask("31", parentId: "120")
        var draft = form.draft
        draft.name = "API"
        let id = try await forms.saveTask(form, draft, uid: "u5")
        XCTAssertEqual(id, "120")
    }

    func testAnUploadedImageIsEmbeddedAtItsAbsoluteUrl() async throws {
        let (forms, server) = makeForms { _ in ["error": 0, "url": "/zentao/file-read-31.png"] as JSON }
        let url = try await forms.uploadImage(uid: "u3", bytes: Data([1, 2, 3]), name: "shot.png")
        XCTAssertEqual(url, "https://z.example.com/zentao/file-read-31.png")
        XCTAssertTrue(try XCTUnwrap(server.requests.last).path.contains("file-ajaxUpload-u3"))
        XCTAssertTrue(try XCTUnwrap(server.requests.last).bodyText.contains("name=\"imgFile\"; filename=\"shot.png\""))
    }

    func testAnImageZenTaoRefusesFailsWithItsReason() async throws {
        let (forms, _) = makeForms { _ in ["error": 1, "message": "too big"] as JSON }
        do {
            _ = try await forms.uploadImage(uid: "u", bytes: Data([1]), name: "a.png")
            XCTFail("expected a failure")
        } catch { XCTAssertEqual(error as? Failure, .validation("too big")) }
    }
}
