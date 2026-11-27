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

    /// The assign forms' own lists: a bug's `users`, a task's `members` (asked for with its execution first).
    func testAssigneesAreReadFromTheAssignForms() async throws {
        let (forms, server) = makeForms { req in
            req.path.contains("bug-assignTo")
                ? wrapped(["users": ["": "", "dante": "D:Dante-HK-Flutter", "dany": "D:Dany_VN_VUE", "closed": "Closed"] as JSON] as JSON)
                : wrapped(["users": ["x": "X:Everyone"] as JSON, "members": ["dany": "D:Dany_VN_VUE"] as JSON] as JSON)
        }
        let bug = try await forms.bugAssignees("7626")
        XCTAssertEqual(Set(bug.map(\.value)), ["dante", "dany"])
        XCTAssertNotNil(try? sent(server, "bug-assignTo-7626.json"))
        let task = try await forms.taskAssignees("14655", executionId: "7")
        XCTAssertEqual(task, [FormOption(value: "dany", label: "D:Dany_VN_VUE")])
        XCTAssertNotNil(try? sent(server, "task-assignTo-7-14655.json"))
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

    /// "Convert to Task": the form is asked for and saved with the bug's id, so ZenTao writes the task on the bug.
    func testATaskMadeFromABugIsAskedForAndSavedWithTheBugsId() async throws {
        let (forms, server) = makeForms { req in
            req.method == "GET" ? wrapped(["task": ["type": "devel", "name": "Wrong text"] as JSON] as JSON) : (["result": "success", "id": 77] as JSON)
        }
        let form = try await forms.newTask("31", fromBug: "7568")
        XCTAssertEqual(form.draft.name, "Wrong text", "ZenTao starts the form from the bug")
        XCTAssertNotNil(try sent(server, "task-create-31-0-0-0-0--7568.json"))
        var draft = form.draft
        draft.assignedTo = "long"
        let id = try await forms.saveTask(form, draft, uid: "u4")
        XCTAssertEqual(id, "77")
        XCTAssertEqual(try sent(server, "task-create-31-0-0-0-0--7568.json").method, "POST")

        // A plain new task keeps its short path.
        let plain = try await forms.newTask("31")
        _ = try await forms.saveTask(plain, plain.draft, uid: "u5")
        XCTAssertTrue(try XCTUnwrap(server.requests.last).path.hasSuffix("task-create-31-0-0.json"))
    }

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

    /// ZenTao keeps an uploaded picture only when the saved text names it by the link ZenTao gave for it; with the
    /// absolute URL the app shows it from, the bug was created and its picture deleted on the server.
    func testThePicturesOfASavedTextAreNamedAsZenTaoNamesThem() {
        let base = "https://z.example.com:4433/zentao"
        let shown = #"<p>Steps</p><p><img src="https://z.example.com:4433/zentao/file-read-34487.png" alt="file-read-34487.png" /></p>"#
        XCTAssertEqual(zentaoOwnImageLinks(shown, baseUrl: base),
                       #"<p>Steps</p><p><img src="/zentao/file-read-34487.png" alt="file-read-34487.png" /></p>"#)
        // A server that answers `index.php?m=file&f=read...` links.
        XCTAssertEqual(zentaoOwnImageLinks(#"<img src="https://z.example.com:4433/zentao/index.php?m=file&amp;f=read&amp;t=png&amp;fileID=7" />"#, baseUrl: base),
                       #"<img src="/zentao/index.php?m=file&amp;f=read&amp;t=png&amp;fileID=7" />"#)
        // Left as they are: a picture of another server, a link that is not a picture, one ZenTao already knows.
        for other in [#"<img src="https://other.example.com/zentao/file-read-1.png" />"#,
                      #"<a href="https://z.example.com:4433/zentao/file-read-2.png">file</a>"#,
                      #"<img src="{34475.png}" alt="x" />"#, #"<img src="/zentao/file-read-3.png" />"#, "plain text"] {
            XCTAssertEqual(zentaoOwnImageLinks(other, baseUrl: base), other)
        }
    }

    func testASavedBugSendsItsPicturesByZenTaosOwnLink() async throws {
        let (forms, server) = makeForms { req in
            req.method == "GET" ? wrapped(["bug": ["productID": 4] as JSON] as JSON) : (["result": "success", "id": 9] as JSON)
        }
        let form = try await forms.newBug("4")
        var draft = form.draft
        draft.title = "Wrong text"
        draft.steps = #"<p><img src="https://z.example.com/zentao/file-read-31.png" alt="file-read-31.png" /></p>"#
        _ = try await forms.saveBug(form, draft, uid: "u7")
        let body = try sent(server, "bug-create-4-0-.json").bodyText.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
        XCTAssertTrue(body.contains(#"src="/zentao/file-read-31.png""#), body)
        XCTAssertFalse(body.contains("https://z.example.com/zentao/file-read-31.png"))
        XCTAssertTrue(body.contains("uid=u7"), "the pictures were uploaded under this uid")
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
