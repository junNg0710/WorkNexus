import CoreDomain
import XCTest
@testable import ToolZenTao

/// Ported from: test/data/zentao_client_test.dart (adapter + client behaviour over a stubbed HTTP server).
final class ZenTaoAdapterTests: XCTestCase {
    // MARK: Session

    func testAuthenticatePostsToTokensAndReturnsTheAccount() async throws {
        let server = StubServer { _ in .json(["token": "tok123"]) }
        let account = try await makeClient(server).authenticate()
        XCTAssertEqual(account, "me")
        XCTAssertEqual(server.requests.count, 1)
        XCTAssertTrue(server.requests[0].path.contains("/api.php/v1/tokens"))
        XCTAssertEqual(server.requests[0].method, "POST")
        // Login body is JSON {account, password}.
        let body = server.requests[0].jsonBody as? JObject
        XCTAssertEqual(body?["account"] as? String, "me")
        XCTAssertEqual(body?["password"] as? String, "pw")
    }

    func testV1RequestsCarryTheTokenHeaderAfterAuth() async throws {
        let server = StubServer { req in .tokenOr(req, token: "tok123") { .json(["id": 1]) } }
        _ = try await makeClient(server).entity("bugs", "1")
        let get = try XCTUnwrap(server.requests.first { $0.path.contains("bugs/1") })
        XCTAssertEqual(get.header("Token"), "tok123")
    }

    func testConcurrentLoginsShareOneTokensRequest() async throws {
        let server = StubServer { req in .tokenOr(req) { .json([:]) } }
        let client = makeClient(server)
        async let a = client.authenticate(), b = client.authenticate(), c = client.authenticate()
        _ = try await (a, b, c)
        XCTAssertEqual(server.requests.filter { $0.path.hasSuffix("/tokens") }.count, 1)
    }

    func testA401ReLogsInOnceAndRetriesWithTheFreshToken() async throws {
        var calls = 0
        var tokens = 0
        let server = StubServer { req in
            if req.path.hasSuffix("/tokens") { tokens += 1; return .json(["token": "tok\(tokens)"]) }
            calls += 1
            return calls == 1 ? .json(["error": "expired"], status: 401) : .json(["id": 9])
        }
        let entity = try await makeClient(server).entity("bugs", "9")
        XCTAssertEqual(entity.idString, "9")
        XCTAssertEqual(tokens, 2)
        let gets = server.requests.filter { $0.path.contains("bugs/9") }
        XCTAssertEqual(gets.map { $0.header("Token") }, ["tok1", "tok2"])
    }

    func testAPersistent401IsSurfacedAfterOneRetry() async throws {
        let server = StubServer { req in .tokenOr(req) { .json(["error": "no"], status: 401) } }
        let res = await makeAdapter(server).listUsers()
        // The 401 comes back as a normal reply, so the (empty) users map parses to no users.
        XCTAssertEqual(server.requests.filter { $0.path.hasSuffix("/users") }.count, 2)
        XCTAssertNotNil(res.value)
    }

    func testTheLanguageCookieIsSentToTheServerOnly() async throws {
        let server = StubServer { req in .tokenOr(req) { .json(["id": 1]) } }
        let client = makeClient(server)
        _ = try await client.entity("bugs", "1")
        let get = try XCTUnwrap(server.requests.first { $0.path.contains("bugs/1") })
        XCTAssertEqual(get.header("Cookie"), "lang=en")
    }

    // MARK: Assigned tickets

    func testListAssignedTicketsParsesTheV1UserResponseIntoUnifiedTickets() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.hasSuffix("/api.php/v1/user") else { return .json([:]) }
                return .json([
                    "profile": ["account": "me"],
                    "bug": ["total": 1, "bugs": [[
                        "id": 1092, "title": "Inventory sync fails", "status": "active", "confirmed": 1, "pri": 1,
                        "assignedTo": "me", "productName": "ERP", "lastEditedDate": "2026-07-16 10:00:00"]]],
                    "task": ["total": 0, "tasks": []],
                    "story": ["total": 0, "stories": []],
                ])
            }
        }
        let tickets = try await makeAdapter(server).listAssignedTickets(sinceCursor: nil).get().tickets
        XCTAssertEqual(tickets.count, 1)
        let t = tickets[0]
        XCTAssertEqual(t.providerType, .zentao)
        XCTAssertEqual(t.externalKey, "1092")
        XCTAssertEqual(t.externalType, "Bug")
        XCTAssertEqual(t.status, .todo)                    // active + confirmed
        XCTAssertEqual(t.title, "Inventory sync fails")
        XCTAssertEqual(t.url, "https://zentao.example.com/bug-view-1092.html")
        XCTAssertEqual(t.id, "zt:bug:1092")
    }

    func testListAssignedTicketsPagesThroughTheUserTotal() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.hasSuffix("/api.php/v1/user") else { return .json([:]) }
                if req.query("fields") == "bug" {
                    // total = 2, but the server hands out one bug per page.
                    let id = req.query("page") == "1" ? 1871 : 3259
                    return .json(["bug": ["total": 2, "bugs": [["id": id, "title": "Bug \(id)", "status": "active", "pri": 2]]]])
                }
                return .json(["task": ["total": 0, "tasks": []]])
            }
        }
        let tickets = try await makeAdapter(server).listAssignedTickets(sinceCursor: nil).get().tickets
        XCTAssertEqual(Set(tickets.map(\.externalKey)), ["1871", "3259"])
    }

    func testAServerIgnoringPageDoesNotLoopForever() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.hasSuffix("/api.php/v1/user") else { return .json([:]) }
                if req.query("fields") == "bug" {
                    return .json(["bug": ["total": 99, "bugs": [["id": 1, "title": "Only", "status": "active"]]]])
                }
                return .json(["task": ["total": 0, "tasks": []]])
            }
        }
        let page = try await makeAdapter(server).listAssignedTickets(sinceCursor: nil).get()
        XCTAssertEqual(page.tickets.count, 1)
        XCTAssertEqual(server.requests.filter { $0.query("fields") == "bug" }.count, 2)
    }

    func testTheCursorFiltersOldTicketsAndTracksTheNewest() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.hasSuffix("/api.php/v1/user") else { return .json([:]) }
                if req.query("fields") == "bug" {
                    return .json(["bug": ["total": 2, "bugs": [
                        ["id": 1, "title": "old", "status": "active", "lastEditedDate": "2026-07-01 10:00:00"],
                        ["id": 2, "title": "new", "status": "active", "lastEditedDate": "2026-07-20 10:00:00"]]]])
                }
                return .json(["task": ["total": 0, "tasks": []]])
            }
        }
        let adapter = makeAdapter(server)
        let first = try await adapter.listAssignedTickets(sinceCursor: nil).get()
        XCTAssertEqual(first.tickets.count, 2)
        XCTAssertEqual(first.nextCursor, "2026-07-20T10:00:00.000")
        let again = try await adapter.listAssignedTickets(sinceCursor: "2026-07-10T00:00:00.000").get()
        XCTAssertEqual(again.tickets.map(\.externalKey), ["2"])
    }

    // MARK: Detail, comments, activity

    func testDetailCommentsAndActivityShareOneDetailRequestPerAdapter() async throws {
        let server = StubServer { req in
            .tokenOr(req, token: "t") {
                guard req.path.hasSuffix("/api.php/v1/bugs/4302") else { return .json([:]) }
                return .json(["id": 4302, "title": "Login loops", "status": "active", "pri": 2,
                              "actions": [["id": 1, "action": "commented", "actor": "thanh", "comment": "Looking into it",
                                           "date": "2026-07-16 10:00:00"]]])
            }
        }
        let adapter = makeAdapter(server)
        _ = await adapter.getTicket(bugTicket())
        _ = await adapter.listComments(bugTicket())
        _ = await adapter.listActivity(bugTicket())
        XCTAssertEqual(server.requests.filter { $0.path.hasSuffix("/api.php/v1/bugs/4302") }.count, 1)
    }

    func testGetTicketReadsTheClassicPageWhenV1AnswersEmpty() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                if req.path.hasSuffix("/api.php/v1/bugs/4302") { return .text("", contentType: "application/json") }
                if req.path.hasSuffix("/bug-view-4302.json") {
                    return .json(wrapped(["bug": ["id": 4302, "title": "Login loops", "status": "active"]]))
                }
                return .json([:])
            }
        }
        let t = try await makeAdapter(server).getTicket(bugTicket()).get()
        XCTAssertEqual(t.externalKey, "4302")
        XCTAssertEqual(t.title, "Login loops")
    }

    func testGetTicketFetchesV1DetailAndKeepsItsHtmlSteps() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.hasSuffix("/api.php/v1/bugs/4302") else { return .json([:]) }
                return .json(["id": 4302, "title": "Login loops", "status": "resolved", "pri": 2,
                              "steps": "<p>Open <strong>login</strong></p><ol><li>step one</li></ol>", "productName": "ERP"])
            }
        }
        let t = try await makeAdapter(server).getTicket(bugTicket()).get()
        XCTAssertEqual(t.title, "Login loops")
        XCTAssertEqual(t.status, .review)              // resolved -> review
        XCTAssertEqual(t.body, "<p>Open <strong>login</strong></p><ol><li>step one</li></ol>")
    }

    func testListCommentsParsesActionsGivenAsAnIdKeyedObject() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.hasSuffix("/api.php/v1/bugs/4302") else { return .json([:]) }
                return .json(["id": 4302, "title": "Login loops", "status": "active",
                              "actions": ordered([
                                "2": ["id": 2, "action": "commented", "actor": ["account": "thanh", "realname": "Thanh"],
                                      "comment": "<p>Fixed in <code>auth.dart</code></p>", "date": "2026-07-16 09:00:00"] as JSON,
                                "1": ["id": 1, "action": "opened", "actor": "system", "comment": "", "date": "2026-07-15 08:00:00"] as JSON,
                              ])])
            }
        }
        let comments = try await makeAdapter(server).listComments(bugTicket()).get()
        // Only the `commented` action becomes a comment (the empty 'opened' drops).
        XCTAssertEqual(comments.count, 1)
        XCTAssertEqual(comments[0].authorName, "Thanh")
        XCTAssertEqual(comments[0].body, "<p>Fixed in <code>auth.dart</code></p>")
    }

    func testListActivityDescribesStateChangesAndLiftsAttachedFiles() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.hasSuffix("/api.php/v1/bugs/4302") else { return .json([:]) }
                return .json(["id": 4302, "title": "x", "status": "active", "actions": [
                    ["id": 1, "action": "opened", "actor": "qa", "date": "2026-07-15 08:00:00"] as JSON,
                    ["id": 2, "action": "activated", "actor": "qa", "date": "2026-07-16 08:00:00",
                     "comment": "Added Files 10.mp4\r\n<p>Recheck please</p>"] as JSON,
                    ["id": 3, "action": "commented", "actor": "qa", "comment": "hi", "date": "2026-07-16 09:00:00"] as JSON,
                ]])
            }
        }
        let events = try await makeAdapter(server).listActivity(bugTicket()).get()
        XCTAssertEqual(events.map(\.action), ["created", "activated"])
        XCTAssertEqual(events[1].detail, "Recheck please")
        XCTAssertEqual(events[1].attachments, ["10.mp4"])
        XCTAssertEqual(events[1].id, "zt:4302:2")
    }

    func testPostCommentPostsToTheClassicCommentAction() async throws {
        let server = StubServer { req in .tokenOr(req) { .json(["result": "success"]) } }
        let comment = try await makeAdapter(server).postComment(bugTicket(), body: "<p>hello</p>").get()
        XCTAssertEqual(comment.body, "<p>hello</p>")
        let req = try XCTUnwrap(server.requests.first { $0.path.contains("action-comment-bug-4302") })
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.field("comment"), "<p>hello</p>")
    }

    // MARK: Write actions (classic channel)

    func testAssignTicketPostsToTheClassicTypeAssignToAction() async throws {
        let server = StubServer { req in .tokenOr(req) { .json(["result": "success"]) } }
        let res = await makeAdapter(server).assignTicket(bugTicket(), assignee: "thanh", comment: "please", left: nil)
        XCTAssertEqual(res.value, true)
        let req = try XCTUnwrap(server.requests.first { $0.path.contains("bug-assignTo-4302") })
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.field("assignedTo"), "thanh")
        XCTAssertEqual(req.field("comment"), "please")
    }

    func testAssigningATaskNamesItsExecutionAndKeepsItsHoursLeft() async throws {
        let server = StubServer { req in .tokenOr(req) { .json(["result": "success"]) } }
        let task = bugTicket(key: "12", type: "Task", entity: .zentaoTask(ZenTaoTaskEntity(execution: "7", left: 2.5)))
        let res = await makeAdapter(server).assignTicket(task, assignee: "thanh", comment: nil, left: nil)
        XCTAssertEqual(res.value, true)
        // `task::assignTo($executionID, $taskID)`: the id alone is read as the execution.
        let req = try XCTUnwrap(server.requests.first { $0.path.contains("task-assignTo-7-12") })
        // ZenTao 20+ resets the hours left to 0 when the field is missing.
        XCTAssertEqual(req.field("left"), "2.5")
    }

    func testAssigningATaskSendsTheHoursLeftTypedIn() async throws {
        let server = StubServer { req in .tokenOr(req) { .json(["result": "success"]) } }
        let task = bugTicket(key: "12", type: "Task", entity: .zentaoTask(ZenTaoTaskEntity(execution: "7")))
        _ = await makeAdapter(server).assignTicket(task, assignee: "thanh", comment: nil, left: 4)
        let req = try XCTUnwrap(server.requests.first { $0.path.contains("task-assignTo-7-12") })
        XCTAssertEqual(req.field("left"), "4")
    }

    func testResolveBugPostsResolutionAndDefaultBuild() async throws {
        let server = StubServer { req in .tokenOr(req) { .json(["result": "success"]) } }
        let res = await makeAdapter(server).resolveBug(bugTicket(), resolution: "fixed", resolvedBuild: nil, assignee: nil, comment: nil)
        XCTAssertEqual(res.value, true)
        let req = try XCTUnwrap(server.requests.first { $0.path.contains("bug-resolve-4302") })
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.field("resolution"), "fixed")
        XCTAssertEqual(req.field("resolvedBuild"), "trunk")
        XCTAssertNotNil(req.field("resolvedDate"))
    }

    func testActivateBugPostsTheDefaultOpenedBuildAndTheActingUser() async throws {
        let server = StubServer { req in .tokenOr(req) { .json(["result": "success"]) } }
        let res = await makeAdapter(server).activateBug(bugTicket(), openedBuild: nil, assignee: nil, comment: nil)
        XCTAssertEqual(res.value, true)
        let req = try XCTUnwrap(server.requests.first { $0.path.contains("bug-activate-4302") })
        XCTAssertEqual(req.field("openedBuild"), "trunk")        // a non-empty string, not an array
        XCTAssertEqual(req.field("assignedTo"), "me")
    }

    func testConfirmBugOn18PostsToBugConfirmBug() async throws {
        let server = StubServer { req in .tokenOr(req) { .json(["result": "success"]) } }
        let res = await makeAdapter(server).confirmBug(bugTicket(), assignee: nil, comment: nil)
        XCTAssertEqual(res.value, true)
        let req = try XCTUnwrap(server.requests.first { $0.method == "POST" && $0.path.contains("bug-confirm") })
        XCTAssertTrue(req.path.contains("bug-confirmBug-4302"))
        XCTAssertEqual(req.field("assignedTo"), "me")
    }

    func testConfirmBugOn20PostsToBugConfirmWithTheBugsOwnFields() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                if req.method == "GET", req.path.contains("bug-confirm-4302") {
                    return .json(["bug": ["id": 4302, "pri": 1, "status": "active", "type": "codeerror",
                                          "deadline": "2026-10-20", "mailto": "an,binh"]])
                }
                return .json(["result": "success"])
            }
        }
        let res = await makeAdapter(server).confirmBug(bugTicket(), assignee: nil, comment: "ok")
        XCTAssertEqual(res.value, true)
        let posts = server.requests.filter { $0.method == "POST" && $0.path.contains("bug-confirm") }
        XCTAssertEqual(posts.count, 1)
        XCTAssertTrue(posts[0].path.contains("bug-confirm-4302"))
        XCTAssertEqual(posts[0].field("assignedTo"), "me")
        XCTAssertEqual(posts[0].field("pri"), "1")
        XCTAssertEqual(posts[0].field("status"), "active")
        XCTAssertEqual(posts[0].field("type"), "codeerror")
        XCTAssertEqual(posts[0].field("deadline"), "2026-10-20")
        XCTAssertEqual(posts[0].form["mailto[]"], ["an", "binh"])
        XCTAssertEqual(posts[0].field("comment"), "ok")
    }

    func testConfirmBugFailsLoudlyWhenZenTaoReturnsHtmlNotJson() async throws {
        let server = StubServer { req in .tokenOr(req) { .html("<!DOCTYPE html><html><body>login</body></html>") } }
        let res = await makeAdapter(server).confirmBug(bugTicket(), assignee: nil, comment: nil)
        XCTAssertNil(res.value)
        XCTAssertNotNil(res.failure)
    }

    func testClassicActionsCarrySiteOriginRefererAndAUid() async throws {
        // ZenTao rejects state-changing POSTs whose Origin/Referer host doesn't match the site; the web client
        // also sends a form uid.
        let server = StubServer { req in .tokenOr(req) { .json(["result": "success"]) } }
        _ = await makeAdapter(server).confirmBug(bugTicket(), assignee: nil, comment: nil)
        let req = try XCTUnwrap(server.requests.first { $0.method == "POST" && $0.path.contains("bug-confirm") })
        XCTAssertEqual(req.header("Origin"), "https://zentao.example.com")
        XCTAssertEqual(req.header("Referer"), "https://zentao.example.com/index.html")
        XCTAssertEqual(req.header("X-Requested-With"), "XMLHttpRequest")
        XCTAssertEqual(req.header("Cookie"), "zentaosid=t; lang=en")
        XCTAssertEqual(req.header("Token"), "t")
        XCTAssertEqual(req.query("zentaosid"), "t")
        XCTAssertNotNil(req.field("uid"))
    }

    func testAnOriginKeepsANonDefaultPort() {
        XCTAssertEqual(ZenTaoClient.origin(of: "https://zt.example.com:8443/zentao"), "https://zt.example.com:8443")
        XCTAssertEqual(ZenTaoClient.origin(of: "https://zt.example.com:443/zentao"), "https://zt.example.com")
    }

    // MARK: Users and containers

    func testListUsersParsesUsersIntoSortedProviderUsers() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.hasSuffix("/api.php/v1/users") else { return .json([:]) }
                return .json(["total": 2, "users": [["account": "zoe", "realname": "Zoe"], ["account": "amy", "realname": "Amy"]]])
            }
        }
        let users = try await makeAdapter(server).listUsers().get()
        XCTAssertEqual(users.map(\.displayName), ["Amy", "Zoe"])
        XCTAssertEqual(users.first?.account, "amy")
        XCTAssertEqual(server.requests.first { $0.path.hasSuffix("/users") }?.query("limit"), "1000")
    }

    func testListProductsAsksForTheTreeAndFilesProductsUnderTheirProgramAndLine() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.hasSuffix("/api.php/v1/products") else { return .json([:]) }
                return .json(["total": 2, "products": [
                    ["id": 1, "name": "VN Program", "type": "program", "children": [
                        ["id": 3, "name": "Mobile", "type": "line", "children": [["id": 8, "name": "Wallet", "type": "normal"]]]]],
                    ["id": 9, "name": "Daily", "type": "normal"],
                ]])
            }
        }
        let products = try await makeAdapter(server).listProducts().get()
        XCTAssertEqual(server.requests.first { $0.path.hasSuffix("/products") }?.query("mergeChildren"), "1")
        XCTAssertEqual(products.map(\.id), ["8", "9"])
        XCTAssertEqual(products.map(\.programName), ["VN Program", nil])
        XCTAssertEqual(products.map(\.lineName), ["Mobile", nil])
    }

    func testListProductsFallsBackToThePlainListWhenTheTreeFails() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.hasSuffix("/api.php/v1/products") else { return .json([:]) }
                if req.query("mergeChildren") != nil { return .text("boom", status: 500) }
                return .json(["total": 1, "products": [["id": 8, "name": "Wallet"]]])
            }
        }
        let products = try await makeAdapter(server).listProducts().get()
        XCTAssertEqual(products.map(\.id), ["8"])
        XCTAssertEqual(products.map(\.programId), [nil])
    }

    func testListProjectsNamesEachProjectsProgramFromPrograms() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                if req.path.hasSuffix("/api.php/v1/projects") {
                    return .json(["total": 2, "projects": [["id": 7, "name": "Wallet", "parent": 3], ["id": 8, "name": "Daily", "parent": 0]]])
                }
                if req.path.hasSuffix("/api.php/v1/programs") { return .json(["total": 1, "programs": [["id": 3, "name": "VN Program"]]]) }
                return .json([:])
            }
        }
        let projects = try await makeAdapter(server).listProjects().get()
        XCTAssertEqual(projects.map(\.id), ["7", "8"])
        XCTAssertEqual(projects.map(\.programId), ["3", nil])
        XCTAssertEqual(projects.map(\.programName), ["VN Program", nil])
    }

    func testListProjectsLeavesProgramsUnnamedWhenProgramsFails() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                if req.path.hasSuffix("/api.php/v1/projects") { return .json(["total": 1, "projects": [["id": 7, "name": "Wallet", "parent": 3]]]) }
                if req.path.hasSuffix("/api.php/v1/programs") { return .text("boom", status: 500) }
                return .json([:])
            }
        }
        let projects = try await makeAdapter(server).listProjects().get()
        XCTAssertEqual(projects.map(\.programName), [nil])
    }

    func testListProjectExecutionsParsesProjectsExecutions() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.hasSuffix("/api.php/v1/projects/3/executions") else { return .json([:]) }
                return .json(["total": 2, "executions": [["id": 12, "name": "Sprint 12"], ["id": 11, "name": "Sprint 11"]]])
            }
        }
        let executions = try await makeAdapter(server).listProjectExecutions(projectId: "3").get()
        XCTAssertEqual(executions.map(\.id), ["12", "11"])
        XCTAssertTrue(executions.allSatisfy { $0.projectId == "3" })
    }

    func testListProductBugsFetchesAllBugsForAProduct() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.hasSuffix("/api.php/v1/products/8/bugs") else { return .json([:]) }
                return .json(["total": 1, "bugs": [["id": 1092, "title": "Product bug", "status": "active", "confirmed": 1, "pri": 2,
                                                    "productName": "VN_Socialfi"]]])
            }
        }
        let page = try await makeAdapter(server).listProductBugs(productId: "8", browseType: nil).get()
        XCTAssertEqual(page.tickets.first?.externalKey, "1092")
        XCTAssertTrue(page.tickets[0].labels.contains("zentao-product:8"))
        let req = try XCTUnwrap(server.requests.first { $0.path.hasSuffix("/api.php/v1/products/8/bugs") })
        XCTAssertEqual(req.query("page"), "1")
        XCTAssertEqual(req.query("limit"), "500")
    }

    func testListProductBugsWithABrowseTypeUsesTheClassicView() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.contains("bug-browse-") else { return .json([:]) }
                return .json(wrapped(["bugs": [["id": 5, "title": "A", "status": "active"]], "pager": ["recTotal": 1]]))
            }
        }
        let page = try await makeAdapter(server).listProductBugs(productId: "8", browseType: "assigntome").get()
        XCTAssertEqual(page.tickets.map(\.externalKey), ["5"])
        XCTAssertTrue(server.requests.contains { $0.path.contains("bug-browse-8-0-assigntome-0-id_desc-0-500-1.json") })
    }
}
