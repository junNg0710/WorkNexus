import CoreDomain
import XCTest
@testable import ToolZenTao

/// Ported from: test/data/zentao_normalize_test.dart, zentao_order_by_test.dart, zentao_ticket_id (id format).
final class ZenTaoNormalizeTests: XCTestCase {
    private func local(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }
    private func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    private func normalize(_ json: JSON, _ type: ZenTaoType, account: String = "ztB", base: String = "https://z") -> Ticket {
        normalizeZenTao(ZenTaoEntity(json: json), type: type, accountId: account, baseUrl: base)
    }

    // MARK: Status / priority

    func testBugActiveDependsOnConfirmed() {
        XCTAssertEqual(mapZenTaoStatus(.bug, "active", confirmed: 0), .inbox)
        XCTAssertEqual(mapZenTaoStatus(.bug, "active", confirmed: 1), .todo)
        XCTAssertEqual(mapZenTaoStatus(.bug, "resolved"), .review)
        XCTAssertEqual(mapZenTaoStatus(.bug, "closed"), .done)
    }

    func testTaskAndStoryStates() {
        XCTAssertEqual(mapZenTaoStatus(.task, "wait"), .todo)
        XCTAssertEqual(mapZenTaoStatus(.task, "doing"), .inprogress)
        XCTAssertEqual(mapZenTaoStatus(.task, "pause"), .blocked)
        XCTAssertEqual(mapZenTaoStatus(.task, "done"), .review)
        XCTAssertEqual(mapZenTaoStatus(.task, "closed"), .done)
        XCTAssertEqual(mapZenTaoStatus(.task, "cancel"), .done)
        XCTAssertEqual(mapZenTaoStatus(.story, "draft"), .inbox)
        XCTAssertEqual(mapZenTaoStatus(.story, "reviewing"), .review)
        XCTAssertEqual(mapZenTaoStatus(.story, "active"), .todo)
    }

    func testPriorityMapsUrgentToLowAndZeroOrNilToMedium() {
        XCTAssertEqual(mapZenTaoPriority(1), .urgent)
        XCTAssertEqual(mapZenTaoPriority(2), .high)
        XCTAssertEqual(mapZenTaoPriority(3), .medium)
        XCTAssertEqual(mapZenTaoPriority(4), .low)
        XCTAssertEqual(mapZenTaoPriority(0), .medium)
        XCTAssertEqual(mapZenTaoPriority(nil), .medium)
    }

    func testTicketIdsAreTypedPerAccount() {
        XCTAssertEqual(zenTaoTicketId(accountId: "zt", type: "Bug", id: "6492"), "zt:bug:6492")
        XCTAssertNotEqual(zenTaoTicketId(accountId: "zt", type: "bug", id: "6492"), zenTaoTicketId(accountId: "zt", type: "task", id: "6492"))
    }

    // MARK: Normalizing

    func testAClosedTicketFiledUnderTheClosedPseudoAccountIsUnassigned() {
        let t = normalize(["id": 8801, "name": "Daily report", "status": "closed", "assignedTo": "closed"], .task,
                          account: "zt", base: "https://zentao.example.com/")
        XCTAssertNil(t.assignee)
        XCTAssertEqual(assigneeHandle(["account": "mobile2"] as JSON), "mobile2")
    }

    func testNormalizesARestV1BugPayload() throws {
        let t = normalize([
            "id": 1092, "title": "Inventory sync fails for warehouse #3",
            "steps": "<p>The sync aborts on a <b>duplicate SKU</b>.</p>", "status": "active", "resolution": "postponed",
            "confirmed": 1, "pri": 1, "severity": 2, "keywords": "sync,inventory", "product": "Internal ERP",
            "assignedTo": ["account": "mobile2", "realname": "Thanh Nguyen"] as JSON,
            "openedBy": ["account": "tester", "realname": "QA One"] as JSON, "openedBuild": "trunk",
            "assignedDate": "2026-07-16T10:00:00Z", "resolvedBy": ["account": "dev", "realname": "Dev One"] as JSON,
            "resolvedDate": "2026-07-17T09:00:00Z", "resolvedBuild": "2026.07",
            "closedBy": ["account": "qa", "realname": "QA Close"] as JSON, "closedDate": "2026-07-18T09:00:00Z",
            "deadline": "2026-07-20", "type": "codeerror", "os": "iOS", "browser": "Safari",
            "openedDate": "2026-07-15T09:00:00Z", "lastEditedDate": "2026-07-17 08:30:00", "projectName": "Mobile App",
            "executionName": "Sprint 24", "storyTitle": "Translate social post", "taskName": "Fix mention parser",
            "planName": "July release",
        ], .bug, account: "ztB", base: "https://zentao.example.com/")

        XCTAssertEqual(t.id, "ztB:bug:1092")
        XCTAssertEqual(t.providerType, .zentao)
        XCTAssertEqual(t.externalType, "Bug")
        XCTAssertEqual(t.status, .todo)                           // active + confirmed=1
        XCTAssertEqual(t.priority, .urgent)                       // pri 1
        XCTAssertEqual(t.severity, 2)
        XCTAssertTrue(t.body.contains("duplicate SKU"))           // kept as ZenTao's editor wrote it: HTML
        XCTAssertTrue(t.body.contains("<b>"))
        // The account handle, not realname, so it stays stable across the LIST and DETAIL shapes.
        XCTAssertEqual(t.assignee, "mobile2")
        XCTAssertTrue(Set(t.labels).isSuperset(of: ["sync", "inventory"]))
        XCTAssertTrue(t.labels.contains("resolution:postponed"))
        XCTAssertEqual(t.url, "https://zentao.example.com/bug-view-1092.html")
        XCTAssertNotNil(t.createdAt)
        XCTAssertNotNil(t.updatedAt)
        XCTAssertEqual(t.projectId, "ztB:Mobile App")     // the first of the product / project / execution names
        XCTAssertEqual(t.sourceHash, contentHash("Inventory sync fails for warehouse #3", t.body))
        guard case .zentaoBug(let bug)? = t.providerEntity else { return XCTFail("expected a bug entity") }
        XCTAssertEqual(bug.confirmed, 1)
        XCTAssertEqual(bug.resolution, "postponed")
        XCTAssertEqual(bug.openedBy, "QA One")
        XCTAssertEqual(bug.openedBuild, "trunk")
        XCTAssertEqual(bug.assignedDate, utc("2026-07-16T10:00:00Z"))
        XCTAssertEqual(bug.resolvedBy, "Dev One")
        XCTAssertEqual(bug.resolvedBuild, "2026.07")
        XCTAssertEqual(bug.closedBy, "QA Close")
        XCTAssertEqual(bug.deadline, "2026-07-20")
        XCTAssertEqual(bug.bugType, "codeerror")
        XCTAssertEqual(bug.os, "iOS")
        XCTAssertEqual(bug.browser, "Safari")
        XCTAssertEqual(bug.projectName, "Mobile App")
        XCTAssertEqual(bug.executionName, "Sprint 24")
        XCTAssertEqual(bug.storyTitle, "Translate social post")
        XCTAssertEqual(bug.taskName, "Fix mention parser")
        XCTAssertEqual(bug.planName, "July release")
        XCTAssertEqual(bug.assignedTo, "mobile2")
    }

    func testTitlesAreDecodedAndBuildsFormatted() {
        let t = normalize(["id": 1, "title": "Say &quot;hi&quot; &amp; bye", "status": "active", "openedBuild": [["id": "trunk", "title": "主干"] as JSON]], .bug)
        XCTAssertEqual(t.title, "Say \"hi\" & bye")
        guard case .zentaoBug(let bug)? = t.providerEntity else { return XCTFail() }
        XCTAssertEqual(bug.openedBuild, "Trunk · 主干")
        XCTAssertEqual(formatZenTaoBuild("trunk"), "trunk")
        XCTAssertNil(formatZenTaoBuild(nil))
    }

    func testHandlesTheZeroDateSentinelAndBareStringAssignee() {
        let t = normalize(["id": 5, "name": "A task", "status": "doing", "pri": 2, "assignedTo": "mobile2",
                           "openedDate": "0000-00-00 00:00:00"], .task)
        XCTAssertNil(t.createdAt)
        XCTAssertEqual(t.assignee, "mobile2")
        XCTAssertEqual(t.status, .inprogress)
    }

    func testStoriesReadTheirSpecAndHaveNoProviderEntity() {
        let t = normalize(["id": 3, "title": "A story", "spec": "<p>spec</p>", "status": "active"], .story)
        XCTAssertEqual(t.externalType, "Story")
        XCTAssertEqual(t.body, "<p>spec</p>")
        XCTAssertNil(t.providerEntity)
        XCTAssertEqual(t.url, "https://z/story-view-3.html")
    }

    // MARK: Activity

    func testActivityDescriptions() {
        func text(_ json: JSON) -> String { zentaoActionText(ZenTaoAction(json: json)) }
        XCTAssertEqual(text(["action": "opened"]), "created")
        XCTAssertEqual(text(["action": "assigned", "extra": "thanh"]), "assigned to thanh")
        XCTAssertEqual(text(["action": "resolved", "extra": "notrepro"]), "resolved · resolution: Irreproducible")
        XCTAssertEqual(text(["action": "resolved", "extra": "fixed"]), "resolved · resolution: Fixed")
        XCTAssertEqual(text(["action": "closed"]), "closed")
        XCTAssertEqual(text(["action": "closed", "extra": "done"]), "closed (done)")
        XCTAssertEqual(text(["action": "edited"]), "edited")
        XCTAssertEqual(text(["action": "bugconfirmed"]), "confirmed the bug")
        XCTAssertEqual(text(["action": ""]), "updated")
        XCTAssertEqual(text(["action": "linked2story"]), "linked2story")
        XCTAssertEqual(text(["action": "assigned", "extra": ["account": "thanh", "realname": "Thanh-VN-Flutter"] as JSON]), "assigned to Thanh-VN-Flutter")
    }

    func testActionAttachmentsSplitTheAddedFilesPrefixFromTheNote() {
        let parsed = zentaoActionAttachments("Added Files 10.mp4\r\n<p>Please recheck on the latest build</p>")
        XCTAssertEqual(parsed.files, ["10.mp4"])
        XCTAssertEqual(parsed.note, "Please recheck on the latest build")
        let plain = zentaoActionAttachments("<p>Reopening this ticket.</p>")
        XCTAssertTrue(plain.files.isEmpty)
        XCTAssertEqual(plain.note, "Reopening this ticket.")
    }

    // MARK: Attachments

    func testMapsTheIdKeyedFilesMapOntoSortedTicketAttachments() throws {
        let t = normalize([
            "id": 2668, "title": "A bug", "status": "active", "activatedCount": 2,
            "files": [
                "11548": ["id": 11548, "title": "bandicam.mp4", "extension": "mp4", "size": 5003944, "addedBy": "Ryan",
                          "addedDate": "2026-05-21 00:00:00", "url": "https://z.example.com/zentao/file-download-11548.json",
                          "webPath": "/zentao/data/upload/1/202605/2114013906a1b2"] as JSON,
                "7931": ["id": 7931, "title": "ScreenRecording.MP4", "extension": "mp4", "size": 39124123, "addedBy": "Ryan"] as JSON,
            ] as JSON,
        ], .bug, base: "https://z.example.com/")
        guard case .zentaoBug(let bug)? = t.providerEntity else { return XCTFail() }
        XCTAssertEqual(bug.activatedCount, 2)
        XCTAssertEqual(bug.attachments.count, 2)
        // Ordered by ascending id (upload order), not map order.
        XCTAssertEqual(bug.attachments[0].id, "7931")
        XCTAssertEqual(bug.attachments[0].size, 39124123)
        // Missing url falls back to a constructed file-download path; a present url is kept verbatim.
        XCTAssertEqual(bug.attachments[0].url, "https://z.example.com/file-download-7931.mp4")
        XCTAssertEqual(bug.attachments[1].url, "https://z.example.com/zentao/file-download-11548.json")
        XCTAssertNotNil(bug.attachments[1].addedDate)
        // webPath (served with byte ranges) becomes the stream URL; without one there is nothing to stream.
        XCTAssertEqual(bug.attachments[1].streamUrl, "https://z.example.com/zentao/data/upload/1/202605/2114013906a1b2")
        XCTAssertNil(bug.attachments[0].streamUrl)
    }

    func testNoFilesMeansEmptyAttachmentsAndNilActivatedCount() {
        let t = normalize(["id": 1, "title": "x", "status": "active"], .bug, account: "z")
        guard case .zentaoBug(let bug)? = t.providerEntity else { return XCTFail() }
        XCTAssertTrue(bug.attachments.isEmpty)
        XCTAssertNil(bug.activatedCount)
    }

    // MARK: Tasks

    func testATaskKeepsWhatItsViewShowsKindScopeSourceAndDates() throws {
        let t = normalize([
            "id": 12897, "name": "Notification layer", "status": "doing", "type": "test", "execution": 31,
            "executionName": "VN_Socialfi", "story": 0, "fromBug": 3218, "estStarted": "0000-00-00", "deadline": "2026-10-20",
            "realStarted": "2026-10-13 17:48:55", "openedBy": ["account": "kan", "realname": "KanDang"] as JSON, "finishedBy": "",
        ], .task)
        guard case .zentaoTask(let task)? = t.providerEntity else { return XCTFail() }
        XCTAssertEqual(task.taskType, "test")
        XCTAssertEqual(task.execution, "31")
        XCTAssertEqual(task.executionName, "VN_Socialfi")
        // ZenTao's "none": no story, no planned start, nobody finished it yet.
        XCTAssertNil(task.story)
        XCTAssertNil(task.estStarted)
        XCTAssertNil(task.finishedBy)
        XCTAssertEqual(task.fromBug, "3218")
        XCTAssertEqual(task.deadline, "2026-10-20")
        XCTAssertEqual(task.realStarted, local(2026, 10, 13, 17, 48, 55))
        XCTAssertEqual(task.openedBy, "KanDang")
    }

    func testASubtaskKeepsItsParentTask() {
        let t = normalize(["id": 12167, "name": "mobile", "status": "wait", "parent": "12160", "parentName": "Chat feature"], .task)
        XCTAssertEqual(t.providerEntity, .zentaoTask(ZenTaoTaskEntity(parentId: "12160", parentName: "Chat feature")))
    }

    func testATaskWithNoParentHasNoneAndOnlyAParentIsOne() {
        let cases: [(JSON, Bool)] = [(["parent": 0], false), (["parent": -1], true), (["parent": 0, "isParent": "1"], true)]
        for (json, isParent) in cases {
            var j: JSON = ["id": 1, "name": "x"]
            j.merge(json) { $1 }
            guard case .zentaoTask(let entity)? = normalize(j, .task).providerEntity else { return XCTFail("\(json)") }
            XCTAssertNil(entity.parentId, "\(json)")
            XCTAssertEqual(entity.isParent, isParent, "\(json)")
        }
    }

    func testATaskKeepsItsHoursAndWhenItReallyStarted() {
        func task(_ json: JSON) -> ZenTaoTaskEntity {
            var j: JSON = ["id": 7, "name": "x"]
            j.merge(json) { $1 }
            guard case .zentaoTask(let e)? = normalize(j, .task).providerEntity else { fatalError() }
            return e
        }
        let started = task(["estimate": "4", "consumed": 1.5, "left": "2.5", "realStarted": "2026-10-01 09:30:00"])
        XCTAssertEqual(started.estimate, 4)
        XCTAssertEqual(started.consumed, 1.5)
        XCTAssertEqual(started.left, 2.5)
        XCTAssertEqual(started.realStarted, local(2026, 10, 1, 9, 30))
        XCTAssertEqual(task(["execution": "31"]).execution, "31")
        XCTAssertEqual(task(["execution": ["id": 31, "name": "S3"] as JSON]).execution, "31")
        XCTAssertNil(task(["execution": 0]).execution)
        XCTAssertEqual(task(["project": "7"]).project, "7")
        XCTAssertNil(task(["project": 0]).project)
        XCTAssertNil(task(["realStarted": "0000-00-00 00:00:00"]).realStarted)
        XCTAssertEqual(task(["openedBy": ["account": "evan", "realname": "Evan"] as JSON]).openedByHandle, "evan")
    }

    func testAParentTaskListsItsSubtasks() {
        let t = normalize([
            "id": 12165, "name": "Notification layer display", "parent": -1,
            "children": ordered([
                "12167": ["id": 12167, "name": "mobile", "status": "wait", "pri": 3,
                          "assignedTo": ["account": "thanh", "realname": "Thanh"] as JSON] as JSON,
                "12166": ["id": 12166, "name": "test", "status": "doing"] as JSON,
            ]),
        ], .task)
        guard case .zentaoTask(let entity)? = t.providerEntity else { return XCTFail() }
        XCTAssertNil(entity.parentId)
        XCTAssertEqual(entity.subtasks, [
            TicketSubtask(id: "12166", title: "test", status: .inprogress),
            TicketSubtask(id: "12167", title: "mobile", status: .todo, priority: 3, assignee: "Thanh"),
        ])
    }

    // MARK: Order by / text helpers

    func testMapsASortToTheFieldNamesOfEachZenTaoList() {
        let title = TicketSort(.title, descending: true)
        XCTAssertEqual(zentaoOrderBy(title, bug: true), "title_desc")
        XCTAssertEqual(zentaoOrderBy(title, bug: false), "name_desc")
        XCTAssertEqual(zentaoOrderBy(TicketSort(.updated), bug: false), "lastEditedDate_asc")
        XCTAssertEqual(zentaoOrderBy(.newest, bug: true), "id_desc")
    }

    func testAColumnTheListCannotSortByFallsBackToTheId() {
        let left = TicketSort(.left)
        XCTAssertEqual(zentaoOrderBy(left, bug: true), "id_asc")
        XCTAssertEqual(zentaoOrderBy(left, bug: false), "left_asc")
        XCTAssertEqual(zentaoOrderBy(TicketSort(.severity), bug: false), "id_asc")
        XCTAssertEqual(zentaoOrderBy(TicketSort(.resolution), bug: true), "resolution_asc")
    }

    func testHtmlEntitiesDecodeNamedAndNumericReferences() {
        XCTAssertEqual(decodeHtmlEntities("a &quot;b&quot; &#39;c&#39; &#x2F; &amp; &unknown; &lt;"), "a \"b\" 'c' / & &unknown; <")
        XCTAssertEqual(decodeHtmlEntities("no entities"), "no entities")
    }

    func testStripHtmlDropsTagsAndKeepsParagraphBreaks() {
        XCTAssertEqual(stripHtml("<p>a&nbsp;b &amp; c</p>\n\n\n\n<p>d</p>"), "a b & c\n\nd")
    }

    func testDatesParseTheZenTaoShapes() {
        XCTAssertEqual(parseZenTaoDate("2026-10-13"), local(2026, 10, 13))
        XCTAssertEqual(parseZenTaoDate("2026-10-13 10:20:30"), local(2026, 10, 13, 10, 20, 30))
        XCTAssertEqual(parseZenTaoDate("2026-10-13T10:20:30Z"), utc("2026-10-13T10:20:30Z"))
        XCTAssertEqual(parseZenTaoDate("2026-10-13T10:20:30+07:00"), utc("2026-10-13T03:20:30Z"))
        XCTAssertNil(parseZenTaoDate("0000-00-00 00:00:00"))
        XCTAssertNil(parseZenTaoDate("not a date"))
        XCTAssertNil(parseZenTaoDate("2026-13-40"))
        XCTAssertNil(parseZenTaoDate(nil))
    }

    func testContentHashIsStableAndMatchesTheDartAlgorithm() {
        // (h*31 + c) & 0x7fffffff over UTF-16 code units, joined as "title body".
        XCTAssertEqual(intHash("a"), 97)
        XCTAssertEqual(intHash("ab"), 97 * 31 + 98)
        XCTAssertEqual(contentHash("a", "b"), String(intHash("a b"), radix: 16))
    }

    func testJsonParserKeepsKeyOrderAndNumberKinds() throws {
        let v = try jsonDecode(#"{"z":1,"a":[true,null,1.0,"xé\n"],"m":{"2":1,"1":2}}"#)
        let o = try XCTUnwrap(v as? JObject)
        XCTAssertEqual(o.keys, ["z", "a", "m"])
        XCTAssertEqual((o["m"] as? JObject)?.keys, ["2", "1"])
        let list = try XCTUnwrap(o["a"] as? [Any])
        XCTAssertEqual(str(list[0]), "true")
        XCTAssertNil(str(list[1]))
        XCTAssertEqual(str(list[2]), "1.0")
        XCTAssertEqual(str(list[3]), "xé\n")
        XCTAssertEqual(str(o["z"]), "1")
        XCTAssertThrowsError(try jsonDecode("{\"a\":"))
        XCTAssertThrowsError(try jsonDecode("<html>"))
        XCTAssertEqual(jsonEncode(v), #"{"z":1,"a":[true,null,1.0,"xé\n"],"m":{"2":1,"1":2}}"#)
    }

    func testPrettyJsonMatchesDartsIndentedEncoder() {
        let o = ordered(["a": 1, "b": [1, 2] as [Any], "c": JObject(), "d": [Any]()])
        XCTAssertEqual(jsonEncode(o, pretty: true), "{\n  \"a\": 1,\n  \"b\": [\n    1,\n    2\n  ],\n  \"c\": {},\n  \"d\": []\n}")
    }
}
