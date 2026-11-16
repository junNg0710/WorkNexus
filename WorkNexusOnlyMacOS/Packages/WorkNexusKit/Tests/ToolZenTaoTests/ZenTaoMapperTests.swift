import CoreDomain
import XCTest
@testable import ToolZenTao

/// Ported from: test/data/zentao_{doc_mapper,doc_history_mapper,doc_html,notification_mapper,dashboard_mapper,product_tree}_test.dart,
/// test/unit/zentao_project_group_test.dart
final class ZenTaoMapperTests: XCTestCase {
    private func local(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }
    private func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    // MARK: Docs

    func testLibrariesMapIdAndNameSkippingRowsWithoutAnId() {
        let libs = mapZenTaoDocLibs(["libs": [["id": 247, "name": "Notification"] as JSON, ["id": 12, "name": ""] as JSON, ["name": "no id"] as JSON]])
        XCTAssertEqual(libs.map { "\($0.id):\($0.name)" }, ["247:Notification", "12:12"])
    }

    func testDocumentListsAcceptAListOrAnIdKeyedMap() {
        let fromList = mapZenTaoDocSummaries(["docs": [["id": 115, "title": "Payloads", "acl": "open"] as JSON]], libId: "247")
        let fromMap = mapZenTaoDocSummaries(["docs": ["116": ["id": 116, "title": "Private", "acl": "private"] as JSON] as JSON], libId: "247")
        XCTAssertEqual(fromList.first?.title, "Payloads")
        XCTAssertEqual(fromList.first?.libId, "247")
        XCTAssertEqual(fromMap.first?.acl, "private")
    }

    func testATextDocumentKeepsItsHtmlAndMetadata() throws {
        let doc = try XCTUnwrap(mapZenTaoDoc([
            "id": 111, "title": "Authz API", "lib": "247", "type": "text", "content": "<div><h1>Authz</h1></div>", "version": 21,
            "addedBy": ["account": "thanh", "realname": "Thanh"] as JSON, "editedDate": "2026-10-07T07:30:07Z", "files": [Any](),
        ], baseUrl: "https://zt.example/zentao"))
        XCTAssertTrue(doc.hasBody)
        XCTAssertFalse(doc.isAttachment)
        XCTAssertEqual(doc.version, 21)
        XCTAssertEqual(doc.author?.displayName, "Thanh")
        XCTAssertEqual(doc.author?.account, "thanh")
        XCTAssertEqual(doc.editedDate, utc("2026-10-07T07:30:07Z"))
    }

    func testAnAttachmentDocumentCarriesItsFiles() throws {
        let doc = try XCTUnwrap(mapZenTaoDoc([
            "id": 115, "title": "Payloads", "lib": 247, "type": "attachment", "content": "",
            "files": [["id": 27696, "title": "Payloads.md", "extension": "txt", "size": 5087] as JSON],
        ], baseUrl: "https://zt.example/zentao"))
        XCTAssertTrue(doc.isAttachment)
        XCTAssertFalse(doc.hasBody)
        XCTAssertEqual(doc.files.first?.title, "Payloads.md")
        XCTAssertEqual(doc.files.first?.url, "https://zt.example/zentao/file-download-27696.txt")
    }

    func testEditorsComeFromEditedListEachOnceTheLastOneNamed() throws {
        let doc = try XCTUnwrap(mapZenTaoDoc([
            "id": 59, "title": "TBUSD", "addedBy": ["account": "Tompham", "realname": "ViPham-VN-go"] as JSON,
            "editedBy": ["account": "Tommy", "realname": "Saul-VN-GO"] as JSON, "editedList": ",Tompham,Tom,Tommy,tom", "views": 42,
        ], baseUrl: ""))
        XCTAssertEqual(doc.author?.displayName, "ViPham-VN-go")
        XCTAssertEqual(doc.editors.map(\.account), ["Tompham", "Tom", "Tommy"])
        XCTAssertEqual(doc.editors.last?.displayName, "Saul-VN-GO")
        XCTAssertEqual(doc.views, 42)
    }

    func testEscapedTitlesReadBackAsPlainText() {
        let docs = mapZenTaoDocSummaries(["docs": [["id": 7, "title": "Post &amp; Restriction"] as JSON]], libId: "89")
        let libs = mapZenTaoDocLibs(["libs": [["id": 1, "name": "A &lt;B&gt;"] as JSON]])
        XCTAssertEqual(docs.first?.title, "Post & Restriction")
        XCTAssertEqual(libs.first?.name, "A <B>")
    }

    func testAReplyWithoutTheDocumentFieldsIsNoDocument() {
        XCTAssertNil(mapZenTaoDoc(["error": "denied"], baseUrl: ""))
    }

    func testPinsRoundTripThroughTheirJson() {
        let pins = ZenTaoDocPins(libs: [ZenTaoDocLib(id: "1", name: "A <B>")], docs: [ZenTaoDocSummary(id: "9", title: "Post & More", libId: "1", acl: "open")])
        XCTAssertEqual(mapZenTaoDocPins(zenTaoDocPinsToJson(pins)), pins)
        XCTAssertTrue(ZenTaoDocPins().isEmpty)
        let toggled = pins.togglingLib(ZenTaoDocLib(id: "2", name: "N")).togglingDoc(pins.docs[0])
        XCTAssertEqual(toggled.libs.map(\.id), ["1", "2"])
        XCTAssertTrue(toggled.docs.isEmpty)
    }

    func testTheDocHtmlDropsTheWhiteBackgroundPinnedOnCodeBlocks() {
        let out = tidyZenTaoDocHtml(#"<pre class="shiki" style="background-color:#FFFFFF;color:#000000;"><code>GET /a</code></pre>"#)
        XCTAssertFalse(out.contains("background-color"))
        XCTAssertTrue(out.contains("<code>GET /a</code>"))
    }

    func testTheDocHtmlDropsAnEmptyTableHeaderRowKeepingTheBody() {
        let out = tidyZenTaoDocHtml("<table><thead><tr><th></th><th></th></tr></thead><tbody><tr><td><strong>Method</strong></td><td>GET</td></tr></tbody></table>")
        XCTAssertFalse(out.contains("<thead>"))
        XCTAssertTrue(out.contains("<td>GET</td>"))
        XCTAssertTrue(tidyZenTaoDocHtml("<table><thead><tr><th>Name</th></tr></thead><tbody></tbody></table>").contains("<th>Name</th>"))
    }

    func testTheDocHtmlDropsBlankParagraphsButKeepsOneHoldingAnImage() {
        let out = tidyZenTaoDocHtml(#"<div><p></p></div><p> </p><p><img src="a.png"></p><p>Text</p>"#)
        XCTAssertEqual(out.components(separatedBy: "<p>").count - 1, 2)
        XCTAssertTrue(out.contains("a.png"))
        XCTAssertEqual(tidyZenTaoDocHtml("   "), "   ")
    }

    func testHistoryEntriesReadTheirDateWhoTheActionAndWhatChanged() {
        let history = mapZenTaoDocHistory(["actions": [
            ["id": 663973, "action": "saveddraft", "hasRendered": true,
             "content": "2026-09-30 12:35:42, <strong>ViPham-VN-go</strong> save draft <strong></strong>.\n"] as JSON,
            ["id": 664003, "action": "edited", "content": "2026-09-30 12:56:37, edited by <strong>ViPham-VN-go</strong> .\n",
             "historyChanges": "<strong><i>Name</i></strong> is changed. The difference is \n<blockquote class='textdiff'>001- <del>Old</del><br />\n001+ <ins>New</ins></blockquote>\n<blockquote class='original'>001- <del>Old</del><br />\n001+ <ins>New</ins></blockquote>"] as JSON,
            ["action": "no id"] as JSON,
        ]])
        XCTAssertEqual(history.count, 2)
        let draft = history[0]
        XCTAssertEqual(draft.id, "663973")
        XCTAssertEqual(draft.action, "saveddraft")
        XCTAssertEqual(draft.date, local(2026, 9, 30, 12, 35, 42))
        XCTAssertEqual(draft.actor, "ViPham-VN-go")
        XCTAssertEqual(draft.summary, "ViPham-VN-go save draft")
        XCTAssertTrue(draft.changes.isEmpty)
        let edit = history[1]
        XCTAssertEqual(edit.summary, "edited by ViPham-VN-go")
        // The diff is read once (its `original` copy skipped).
        XCTAssertEqual(edit.changes.count, 1)
        XCTAssertEqual(edit.changes[0].field, "Name")
        XCTAssertEqual(edit.changes[0].removed, ["Old"])
        XCTAssertEqual(edit.changes[0].added, ["New"])
    }

    func testNoListIsNoHistory() { XCTAssertTrue(mapZenTaoDocHistory(["actions": "x"]).isEmpty) }

    func testAFieldReadsItsOldAndNewValueTheBodyOnlyThatItChanged() {
        let changes = parseZenTaoDocChanges(#"<strong><i>Status</i></strong> is changed. It was "Draft" and it is "Released".<br />"# + "\n"
            + #"<strong><i>rawContent</i></strong> is changed. It was "" and it is "{"type":"page"}".<br />"# + "\n")
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes[0].field, "Status")
        XCTAssertEqual(changes[0].from, "Draft")
        XCTAssertEqual(changes[0].to, "Released")
        XCTAssertTrue(changes[1].isBody)
        XCTAssertNil(changes[1].to)           // no raw JSON kept
    }

    func testMiniHtmlRoundTripsEntitiesAndVoidTags() {
        let fragment = HNode.parseFragment(#"<p class="a">x &amp; y<br>z</p><img src='a.png'><!-- c -->"#)
        XCTAssertEqual(fragment.plainText, "x & yz")
        XCTAssertEqual(fragment.innerHtml, #"<p class="a">x &amp; y<br>z</p><img src="a.png"><!-- c -->"#)
        XCTAssertEqual(fragment.firstElement("p")?.classes, ["a"])
    }

    // MARK: Notifications

    private var notificationView: JSON {
        [
            "unreadCount": 2,
            "allMessages": ordered([
                "2026-10-09": [[
                    "id": "301", "status": "sended", "createdDate": "2026-10-09 11:06:12",
                    "data": "JunNg-VN-Flutter assigned Bug <a data-url='https://zt.example/zentao/bug-view-6492.html' href='###' onclick='clickMessage(this)'>[#6492::[Discover] Feed: video &amp; autoplay]</a>",
                ] as JSON],
                "2026-10-06": [
                    ["id": 290, "status": "read", "createdDate": "2026-10-06 10:45:00",
                     "data": "Luci finished Task <a href='https://zt.example/zentao/index.php?m=task&amp;f=view&amp;taskID=12492'>[#12492::Livestream share]</a>"] as JSON,
                    ["id": "289", "status": "wait", "data": "Plain text, no link"] as JSON,
                    ["id": "", "data": "no id — skipped"] as JSON,
                ],
            ]),
        ]
    }

    func testNotificationsReadEveryMessageWithAnId() {
        let items = zenTaoNotificationsFromView(notificationView, accountId: "a1")
        XCTAssertEqual(items.map(\.id), ["301", "290", "289"])
        XCTAssertTrue(items.allSatisfy { $0.accountId == "a1" })
    }

    func testNotificationsSplitTheSummaryFromTheLinkedObject() {
        let n = zenTaoNotificationsFromView(notificationView, accountId: "a1")[0]
        XCTAssertEqual(n.summary, "JunNg-VN-Flutter assigned Bug")
        XCTAssertEqual(n.objectType, "bug")
        XCTAssertEqual(n.objectId, "6492")
        XCTAssertEqual(n.objectTitle, "[Discover] Feed: video & autoplay")
        XCTAssertEqual(n.url, "https://zt.example/zentao/bug-view-6492.html")
        XCTAssertFalse(n.read)
        XCTAssertEqual(n.createdAt, local(2026, 10, 9, 11, 6, 12))
    }

    func testNotificationsReadTheObjectFromAQueryStyleLinkAndTheReadStatus() {
        let n = zenTaoNotificationsFromView(notificationView, accountId: "a1")[1]
        XCTAssertEqual(n.objectType, "task")
        XCTAssertEqual(n.objectId, "12492")
        XCTAssertEqual(n.objectTitle, "Livestream share")
        XCTAssertTrue(n.read)
    }

    func testAMessageWithoutALinkKeepsItsWholeText() {
        let n = zenTaoNotificationsFromView(notificationView, accountId: "a1")[2]
        XCTAssertEqual(n.summary, "Plain text, no link")
        XCTAssertNil(n.objectType)
        XCTAssertNil(n.url)
        XCTAssertNil(n.createdAt)
        XCTAssertTrue(zenTaoNotificationsFromView([:], accountId: "a1").isEmpty)
        XCTAssertTrue(zenTaoNotificationsFromView(["allMessages": [Any]()], accountId: "a1").isEmpty)
    }

    // MARK: Dashboard

    private var dashboardReply: JSON {
        [
            "profile": ["id": 12, "account": "thanh", "realname": "Thanh Nguyen", "role": ["code": "dev", "name": "Developer"] as JSON,
                        "email": "thanh@example.com", "last": "2026-10-09T03:12:00Z"] as JSON,
            "task": ["total": "17", "tasks": [
                ["id": "881", "name": "Build dashboard", "status": "doing", "pri": "2", "deadline": "2026-10-12", "executionName": "Sprint 42"] as JSON,
                ["name": "no id — skipped"] as JSON]] as JSON,
            "bug": ["total": 3, "bugs": ["4302": ["id": 4302, "title": "Crash on login", "status": "active", "statusName": "Active", "pri": 1,
                                                  "deadline": "0000-00-00", "productName": "TBChat"] as JSON] as JSON] as JSON,
            "todo": ["total": 1, "todos": [["id": 5, "name": "Standup", "status": "wait", "date": "2030-01-01"] as JSON]] as JSON,
            "execution": ["total": 1, "executions": [["id": 42, "name": "Sprint 42", "projectName": "TBChat", "status": "doing",
                                                      "hours": ["progress": "62.5"] as JSON, "end": "2026-10-20"] as JSON]] as JSON,
            "actions": [["id": 9001, "objectType": "Bug", "objectID": "4302", "objectName": "Crash on login", "action": "resolved",
                         "actionLabel": "resolved", "actor": ["account": "terry", "realname": "Terry"] as JSON, "date": "2026-10-09 10:22:11"] as JSON],
            "contribute": ["involvedProjectTotal": "4", "ownerProductTotal": 0, "docCreatedTotal": 7] as JSON,
        ]
    }

    func testTheDashboardReadsTheProfileRoleNameIncluded() {
        let fetched = local(2026, 10, 9, 12)
        let d = zenTaoDashboardFromJson(dashboardReply, accountId: "a1", fetchedAt: fetched)
        XCTAssertEqual(d.accountId, "a1")
        XCTAssertEqual(d.fetchedAt, fetched)
        XCTAssertEqual(d.profile.account, "thanh")
        XCTAssertEqual(d.profile.realname, "Thanh Nguyen")
        XCTAssertEqual(d.profile.role, "Developer")
        XCTAssertEqual(d.profile.lastLogin, utc("2026-10-09T03:12:00Z"))
    }

    func testTheDashboardReadsWorkListsFromArraysAndIdKeyedObjects() throws {
        let d = zenTaoDashboardFromJson(dashboardReply, accountId: "a1", fetchedAt: Date())
        XCTAssertEqual(d.taskTotal, 17)
        let task = try XCTUnwrap(d.tasks.first)
        XCTAssertEqual(d.tasks.count, 1)
        XCTAssertEqual(task.kind, .task)
        XCTAssertEqual(task.id, "881")
        XCTAssertEqual(task.title, "Build dashboard")
        XCTAssertEqual(task.priority, 2)
        XCTAssertEqual(task.deadline, local(2026, 10, 12))
        XCTAssertEqual(task.context, "Sprint 42")
        let bug = try XCTUnwrap(d.bugs.first)
        XCTAssertEqual(bug.id, "4302")
        XCTAssertEqual(bug.statusLabel, "Active")
        XCTAssertNil(bug.deadline)                     // 0000-00-00 is no date
        XCTAssertEqual(bug.context, "TBChat")
        XCTAssertEqual(d.todos.first?.kind, .todo)
        XCTAssertNil(d.todos.first?.deadline)          // a future todo has no date
    }

    func testTheDashboardReadsExecutionsActivityAndCounters() throws {
        let d = zenTaoDashboardFromJson(dashboardReply, accountId: "a1", fetchedAt: Date())
        let e = try XCTUnwrap(d.executions.first)
        XCTAssertEqual(e.name, "Sprint 42")
        XCTAssertEqual(e.projectName, "TBChat")
        XCTAssertEqual(e.progress, 62.5)
        XCTAssertEqual(d.executionTotal, 1)
        let a = try XCTUnwrap(d.activities.first)
        XCTAssertEqual(a.actor, "Terry")
        XCTAssertEqual(a.action, "resolved")
        XCTAssertEqual(a.objectType, "bug")
        XCTAssertEqual(a.objectId, "4302")
        XCTAssertEqual(d.projectTotal, 4)
        XCTAssertEqual(d.productTotal, 0)
        XCTAssertEqual(d.docTotal, 7)
    }

    func testMissingDashboardBlocksBecomeEmptyListsAndNilCounters() {
        let bare = zenTaoDashboardFromJson(["profile": ["account": "thanh"] as JSON], accountId: "a1", fetchedAt: Date())
        XCTAssertEqual(bare.profile.realname, "thanh")
        XCTAssertTrue(bare.stories.isEmpty)
        XCTAssertEqual(bare.storyTotal, 0)
        XCTAssertTrue(bare.activities.isEmpty)
        XCTAssertNil(bare.projectTotal)
    }

    // MARK: Profile

    func testTheProfileMapsDepartmentsRolesAndTheAvatarUrl() throws {
        let departments: [JSON] = [["id": 1, "name": "VN", "parent": 0], ["id": 2, "name": "Flutter VN", "parent": 1]]
        XCTAssertEqual(zenTaoDepartmentPath(2, departments), "VN > Flutter VN")
        XCTAssertNil(zenTaoDepartmentPath(0, departments))
        XCTAssertEqual(mapZenTaoDepartments(departments).map(\.path), ["VN", "VN > Flutter VN"])
        let profile = try mapZenTaoProfile(accountId: "a1", [
            "profile": ["id": 12, "account": "thanh", "realname": "Thanh", "dept": 2, "departmentPath": "VN > Flutter VN",
                        "role": ["code": "dev", "name": "Developer"] as JSON, "avatar": "/zentao/data/avatar.png", "join": "0000-00-00",
                        "email": "t@example.com", "visits": "7"] as JSON,
        ], baseUrl: "https://zt.example/zentao")
        XCTAssertEqual(profile.userId, 12)
        XCTAssertEqual(profile.departmentId, 2)
        XCTAssertEqual(profile.department, "VN > Flutter VN")
        XCTAssertEqual(profile.role, "Developer")
        XCTAssertEqual(profile.roleCode, "dev")
        XCTAssertEqual(profile.avatarUrl, "https://zt.example/zentao/data/avatar.png")
        XCTAssertNil(profile.joined)
        XCTAssertEqual(profile.visits, 7)
        XCTAssertThrowsError(try mapZenTaoProfile(accountId: "a1", [:]))
    }

    // MARK: Product / project trees

    private let productTree: JSON = [
        "page": 1, "total": 5, "limit": 100,
        "products": [
            ["id": 1, "name": "VN Program", "type": "program", "unclosedTotal": 4, "children": [
                ["id": 30, "name": "Mobile", "type": "line", "children": [
                    ["id": 12, "name": "Wallet", "type": "normal"] as JSON, ["id": 13, "name": "Chat", "type": "branch"] as JSON]] as JSON,
                ["id": 14, "name": "Website", "type": "platform"] as JSON]] as JSON,
            // PHP's keyed arrays come as JSON objects.
            ["id": 31, "name": "Tools", "type": "line", "children": ["15": ["id": 15, "name": "Code Security Review", "type": "normal"] as JSON] as JSON] as JSON,
            ["id": 16, "name": "Daily Work Log", "type": "normal"] as JSON,
            ["id": 17, "name": "Archive", "type": "normal"] as JSON,
        ],
    ]

    private func provider(_ p: ZenTaoProduct) -> ProviderProduct {
        ProviderProduct(id: p.id, name: p.name, accountId: "zt", programId: p.programId, programName: p.programName, lineId: p.lineId, lineName: p.lineName)
    }

    func testTheMergedTreeReadsAsProductsFiledUnderProgramAndLine() {
        let products = ZenTaoProductsResponse(json: productTree).products
        XCTAssertEqual(products.map { [$0.id, $0.name, $0.programName ?? "-", $0.lineName ?? "-"] }, [
            ["12", "Wallet", "VN Program", "Mobile"], ["13", "Chat", "VN Program", "Mobile"], ["14", "Website", "VN Program", "-"],
            ["15", "Code Security Review", "-", "Tools"], ["16", "Daily Work Log", "-", "-"], ["17", "Archive", "-", "-"],
        ])
    }

    func testProductsGroupByProgramThenLineInZenTaosOrder() {
        let tree = ZenTaoProductTree.of(ZenTaoProductsResponse(json: productTree).products.map(provider))
        XCTAssertEqual(tree.groups.map(\.id), ["program:1", "line:31"])
        XCTAssertEqual(tree.groups.map(\.name), ["VN Program", "Tools"])
        let program = tree.groups[0]
        XCTAssertEqual(program.lines.map(\.name), ["Mobile"])
        XCTAssertEqual(program.lines[0].products.map(\.name), ["Wallet", "Chat"])
        XCTAssertEqual(program.products.map(\.name), ["Website"])
        XCTAssertEqual(program.allProducts.map(\.id), ["12", "13", "14"])
        // No folder made up from a name: "Code ..." stays in its real line.
        XCTAssertEqual(tree.groups[1].products.map(\.name), ["Code Security Review"])
        // The loose products read by name; folders keep ZenTao's order.
        XCTAssertEqual(tree.ungrouped.map(\.name), ["Archive", "Daily Work Log"])
    }

    func testAPlainProductListStaysFlatSortedByName() {
        let plain = ZenTaoProductsResponse(json: ["total": 2, "products": [["id": 2, "name": "Wallet", "type": "normal", "program": 1] as JSON, ["id": 1, "name": "Chat", "type": "normal"] as JSON]]).products
        let tree = ZenTaoProductTree.of(plain.map(provider))
        XCTAssertTrue(tree.groups.isEmpty)
        XCTAssertEqual(tree.ungrouped.map(\.name), ["Chat", "Wallet"])
    }

    private func project(_ id: String, _ name: String, _ programId: String? = nil, _ programName: String? = nil) -> ProviderProject {
        ProviderProject(id: id, name: name, accountId: "zt", programId: programId, programName: programName)
    }

    func testAProjectsProgramIsItsParent() {
        let p = ZenTaoProject(json: ["id": 7, "name": "Wallet", "parent": 3, "path": ",3,7,"])
        XCTAssertEqual(p.programId, "3")
        XCTAssertNil(p.programName)
        XCTAssertEqual(ZenTaoProject(json: ["id": 7, "program": "5"]).programId, "5")
        XCTAssertNil(ZenTaoProject(json: ["id": 7, "parent": 0]).programId)
    }

    func testProgramsNameProgramsSubProgramsIncluded() {
        let res = ZenTaoProgramsResponse(json: ["total": 2, "programs": [["id": 3, "name": "VN Program", "children": [["id": 4, "name": "Wallet line"] as JSON]] as JSON]])
        XCTAssertEqual(res.names.map(\.id), ["3", "4"])
        XCTAssertEqual(res.names.map(\.name), ["VN Program", "Wallet line"])
    }

    func testProjectsGroupByProgramInZenTaosOrderTheRestAfter() {
        let tree = ZenTaoProjectTree.of([project("1", "VN_Wallet", "3", "Mobile"), project("2", "HK_Chat", "9", "Asia"),
                                         project("3", "VN_Chat", "3", "Mobile"), project("4", "Zed"), project("5", "Alpha")])
        XCTAssertEqual(tree.groups.map(\.name), ["Mobile", "Asia"])
        XCTAssertEqual(tree.groups[0].projects.map(\.id), ["1", "3"])
        XCTAssertEqual(tree.ungrouped.map(\.name), ["Alpha", "Zed"])
        // No program known: flat, by name.
        let flat = ZenTaoProjectTree.of([project("1", "b"), project("2", "A")])
        XCTAssertTrue(flat.groups.isEmpty)
        XCTAssertEqual(flat.ungrouped.map(\.name), ["A", "b"])
    }
}
