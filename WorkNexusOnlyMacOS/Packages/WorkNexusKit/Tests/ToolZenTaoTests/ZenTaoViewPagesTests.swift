import CoreDomain
import XCTest
@testable import ToolZenTao

/// Ported from: test/data/zentao_client_test.dart (classic list views, base URL probing, task bugs, assets)
final class ZenTaoViewPagesTests: XCTestCase {
    func testListExecutionTasksPageFetchesOnePageOfATaskStatusView() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.contains("execution-task-") else { return .json([:]) }
                return .json(wrapped([
                    "tasks": ordered([
                        "8801": ordered(["id": 8801, "name": "Wire the task board", "status": "done",
                                         "children": ordered(["8802": ["id": 8802, "name": "Sub", "status": "done"] as JSON])]),
                        "8800": ["id": 8800, "name": "Older", "status": "done"] as JSON,
                    ]),
                    "pager": ["recTotal": 5],
                ]))
            }
        }
        let adapter = makeAdapter(server)
        let second = try await adapter.listExecutionTasksPage(executionId: "12", browseType: "done", page: 2, limit: 2,
                                                              sort: .newest, cancel: nil).get()
        let last = try await adapter.listExecutionTasksPage(executionId: "12", browseType: "done", page: 3, limit: 2,
                                                            sort: TicketSort(.priority), cancel: nil).get()

        let paths = server.requests.map(\.path).filter { $0.contains("task") }
        XCTAssertTrue(paths[0].contains("execution-task-12-done-0-id_desc-0-2-2.json"))
        // A sort goes to ZenTao as the list's orderBy.
        XCTAssertTrue(paths[1].contains("execution-task-12-done-0-pri_asc-0-2-3.json"))
        // A parent task is followed by its subtasks.
        XCTAssertEqual(second.tickets.map(\.externalKey), ["8801", "8802", "8800"])
        XCTAssertEqual(second.tickets.first?.externalType, "Task")
        XCTAssertTrue(second.tickets.allSatisfy { $0.labels.contains("zentao-execution:12") })
        XCTAssertEqual(second.total, 5)
        XCTAssertTrue(second.hasMore)
        // ZenTao answers past the end with page 1 again: the total ends it.
        XCTAssertFalse(last.hasMore)
    }

    func testListExecutionTasksPageFailsOnAReplyThatCarriesNoTaskList() async throws {
        var expired = true
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.contains("execution-task-") else { return .json([:]) }
                // 18.x answers an expired session by sending it to log in.
                let inner: JSON = expired ? ["locate": "/user-login.html"] : ["tasks": [Any](), "pager": ["recTotal": 0] as JSON]
                return .json(wrapped(inner))
            }
        }
        let adapter = makeAdapter(server)
        func load() async -> Outcome<ViewPage> {
            await adapter.listExecutionTasksPage(executionId: "12", browseType: "wait", page: 1, limit: 50, sort: .newest, cancel: nil)
        }
        // Not an empty view: that would hide the column's cached tasks.
        let failed = await load()
        XCTAssertNotNil(failed.failure)

        expired = false
        let empty = try await load().get()
        XCTAssertTrue(empty.tickets.isEmpty)
        XCTAssertFalse(empty.hasMore)
    }

    func testListProductBugsPageFetchesOnePageOfABugViewAndItsTotal() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.contains("bug-browse-") else { return .json([:]) }
                return .json(wrapped([
                    "bugs": ordered(["12": ["id": 12, "title": "A", "status": "resolved"] as JSON,
                                     "11": ["id": 11, "title": "B", "status": "resolved"] as JSON]),
                    "pager": ["recTotal": 5],
                ]))
            }
        }
        let adapter = makeAdapter(server)
        let second = try await adapter.listProductBugsPage(productId: "4", browseType: "toclosed", page: 2, limit: 2, sort: .newest, cancel: nil).get()
        let last = try await adapter.listProductBugsPage(productId: "4", browseType: "toclosed", page: 3, limit: 2, sort: .newest, cancel: nil).get()

        let paths = server.requests.map(\.path).filter { $0.contains("bug") }
        XCTAssertTrue(paths[0].contains("bug-browse-4-0-toclosed-0-id_desc-0-2-2.json"))
        XCTAssertTrue(paths[1].contains("bug-browse-4-0-toclosed-0-id_desc-0-2-3.json"))
        XCTAssertEqual(second.tickets.map(\.externalKey), ["12", "11"])
        XCTAssertTrue(second.tickets[0].labels.contains("zentao-product:4"))
        XCTAssertEqual(second.total, 5)
        XCTAssertTrue(second.hasMore)
        XCTAssertFalse(last.hasMore)
    }

    func testClassicRequestsCarryTheSessionAsQueryParamAndTokenHeader() async throws {
        let server = StubServer { req in
            .tokenOr(req, token: "sid9") { .json(wrapped(["bugs": [Any](), "pager": ["recTotal": 0]])) }
        }
        _ = try await makeAdapter(server).listProductBugsPage(productId: "4", browseType: "all", page: 1, limit: 10, sort: .newest, cancel: nil).get()
        let req = try XCTUnwrap(server.requests.first { $0.path.contains("bug-browse-") })
        XCTAssertEqual(req.query("zentaosid"), "sid9")
        XCTAssertEqual(req.header("Token"), "sid9")
    }

    func testAPageRequestIsCancelledWhenItsSignalFires() async throws {
        let server = StubServer { req in .tokenOr(req) { .json(wrapped(["bugs": [Any](), "pager": ["recTotal": 0]])) } }
        let signal = CancelSignal()
        signal.cancel()
        let res = await makeAdapter(server).listProductBugsPage(productId: "4", browseType: "all", page: 1, limit: 10, sort: .newest, cancel: signal)
        XCTAssertEqual(res.failure, .cancelled("ZenTao request cancelled"))
    }

    // MARK: detectBaseUrl

    func testDetectBaseUrlAppendsZentaoWhenTheHostRootHasNoApi() async throws {
        let server = StubServer { req in
            if req.path == "/zentao/api.php/v1/tokens" {
                return req.bodyText == "{}" ? .json(["error": "bad login"], status: 400) : .json(["token": "tok"])
            }
            return .html("<h1>Not Found</h1>", status: 404)
        }
        let client = makeClient(server)
        let root = try await client.detectBaseUrl()
        XCTAssertEqual(root, "https://zentao.example.com/zentao")
        XCTAssertEqual(client.baseUrl, "https://zentao.example.com/zentao")
        try await client.authenticate()
        XCTAssertEqual(server.requests.last?.path, "/zentao/api.php/v1/tokens")
    }

    func testDetectBaseUrlKeepsTheEnteredUrlWhenItAlreadyServesTheApi() async throws {
        let server = StubServer { _ in .json(["error": "bad login"], status: 400) }
        let client = makeClient(server)
        let root = try await client.detectBaseUrl()
        XCTAssertEqual(root, "https://zentao.example.com")
        XCTAssertEqual(server.requests.count, 1)
    }

    func testDetectBaseUrlKeepsTheEnteredUrlWhenNoCandidateServesTheApi() async throws {
        let client = makeClient(StubServer { _ in .html("<h1>Not Found</h1>", status: 404) })
        let root = try await client.detectBaseUrl()
        XCTAssertEqual(root, "https://zentao.example.com")
    }

    func testCandidateBaseUrlsDoNotDoubleTheZentaoSuffix() {
        XCTAssertEqual(ZenTaoClient.candidateBaseUrls("host.example.com/zentao/"), ["https://host.example.com/zentao"])
        XCTAssertEqual(ZenTaoClient.candidateBaseUrls("https://h.example.com/api.php/v1"),
                       ["https://h.example.com", "https://h.example.com/zentao"])
    }

    func testTestConnectionReportsTheAccountAndTheRootItReached() async throws {
        let server = StubServer { req in
            if req.path == "/zentao/api.php/v1/tokens" { return req.bodyText == "{}" ? .json(["error": "bad login"], status: 400) : .json(["token": "tok"]) }
            return .html("nope", status: 404)
        }
        let check = try await makeAdapter(server).testConnection().get()
        XCTAssertTrue(check.ok)
        XCTAssertEqual(check.account, "me")
        XCTAssertEqual(check.baseUrl, "https://zentao.example.com/zentao")
    }

    func testABadLoginFailsAuthenticateAndTestConnection() async throws {
        let server = StubServer { req in req.path.hasSuffix("/tokens") ? .json(["error": "bad login"], status: 400) : .json([:]) }
        do {
            try await makeClient(server).authenticate()
            XCTFail("a login without a token must throw")
        } catch let e as ZenTaoError {
            XCTAssertTrue(e.message.contains("no token"))
        }
        let res = await makeAdapter(server).testConnection()
        XCTAssertNotNil(res.failure)
    }

    // MARK: Task bugs

    private func serveTaskBugs(_ pages: [[Int]], total: Int) -> (StubServer, ZenTaoProviderAdapter) {
        var id = 100
        let server = StubServer { req in
            .tokenOr(req) {
                guard req.path.contains("execution-bug-") else { return .json([:]) }
                let re = try! NSRegularExpression(pattern: #"-(\d+)\.json$"#)
                let m = re.firstMatch(in: req.path, range: NSRange(location: 0, length: (req.path as NSString).length))!
                let page = Int((req.path as NSString).substring(with: m.range(at: 1)))!
                var bugs: [Any] = []
                for task in pages[page - 1] { bugs.append(["id": id, "title": "Bug", "status": "active", "task": task] as JSON); id += 1 }
                return .json(wrapped(["bugs": bugs, "pager": ["recTotal": total]]))
            }
        }
        return (server, makeAdapter(server))
    }

    private func bugPaths(_ server: StubServer) -> [String] {
        server.requests.map { $0.path.removingPercentEncoding ?? $0.path }.filter { $0.contains("execution-bug") }
    }

    func testTaskBugsSortedByTaskStopAtTheFirstLowerTask() async throws {
        let (server, adapter) = serveTaskBugs([[12000, 11548, 11548], [11548, 11000, 0], [0, 0, 0]], total: 9)
        let got = try await adapter.listTaskBugs(executionId: "31", taskId: 11548, limit: 3).get()
        let paths = bugPaths(server)
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths[0].contains("execution-bug-31-0-all-task_desc,id_desc-0-all-0-0-3-1.json"))
        XCTAssertTrue(paths[1].contains("execution-bug-31-0-all-task_desc,id_desc-0-all-0-0-3-2.json"))
        let tasks = got.bugs.map { b -> String? in if case .zentaoBug(let e) = b.providerEntity { return e.task } else { return nil } }
        XCTAssertEqual(tasks, ["12000", "11548", "11548", "11548", "11000", "0"])
        XCTAssertFalse(got.complete)
        XCTAssertEqual(got.above, 0)
    }

    func testATaskBugListReadToItsEndCoversEveryTask() async throws {
        let (_, adapter) = serveTaskBugs([[9, 8]], total: 2)
        let got = try await adapter.listTaskBugs(executionId: "31", taskId: 5, limit: 3).get()
        XCTAssertTrue(got.complete)
    }

    func testUnsortedTaskBugsReadOnToTheEnd() async throws {
        let (server, adapter) = serveTaskBugs([[5, 9, 1], [7, 2, 3], [4]], total: 7)
        let got = try await adapter.listTaskBugs(executionId: "31", taskId: 8, limit: 3).get()
        XCTAssertEqual(bugPaths(server).count, 3)
        XCTAssertEqual(got.bugs.count, 7)
        XCTAssertTrue(got.complete)
    }

    func testUnsortedPastItsLastPageItCoversNoRange() async throws {
        let (_, adapter) = serveTaskBugs([[5, 9], [7, 2]], total: 10)
        let got = try await adapter.listTaskBugs(executionId: "31", taskId: 8, limit: 2, maxPages: 2).get()
        XCTAssertFalse(got.complete)
        XCTAssertNil(got.above)
    }

    // MARK: Assets

    func testStreamRequestHandsAPlayerTheSessionForAnOnServerFile() async throws {
        let server = StubServer { req in .tokenOr(req, token: "tok123") { .json([:]) } }
        let client = makeClient(server)
        let req = try await client.streamRequest("/file-download-7.mp4")
        XCTAssertEqual(req?.url.host, "zentao.example.com")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(req?.url), resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "zentaosid" }?.value, "tok123")
        XCTAssertEqual(req?.headers, ["Cookie": "zentaosid=tok123", "Token": "tok123"])
        // Another host never receives the session.
        let other = try await client.streamRequest("https://cdn.example.org/a.mp4")
        XCTAssertNil(other)
    }

    func testFetchBytesAcceptsImagesOnlyAndSendsTheSession() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let server = StubServer { req in
            .tokenOr(req) {
                req.path.contains("file-read-1") ? .bytes(png, contentType: "image/png") : .html("<html>login</html>")
            }
        }
        let client = makeClient(server)
        let image = try await client.fetchBytes("/file-read-1.png")
        XCTAssertEqual(image, png)
        let asset = try XCTUnwrap(server.requests.first { $0.path.contains("file-read-1") })
        XCTAssertEqual(asset.header("Cookie"), "zentaosid=t; lang=en")
        XCTAssertEqual(asset.query("zentaosid"), "t")
        // A login page is never taken for an image.
        let notImage = try await client.fetchBytes("/file-read-2.png")
        XCTAssertNil(notImage)
    }

    /// A real 1x1 PNG, for checks that read the bytes as a picture.
    private static let onePixelPng = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    /// Some uploads come back as `application/octet-stream`: a picture is told by its bytes, so it still shows.
    func testAnImageServedWithoutAnImageTypeIsTakenByItsBytes() async throws {
        let png = Self.onePixelPng
        let server = StubServer { req in
            .tokenOr(req) { req.path.contains("file-read-34105") ? .bytes(png, contentType: "application/octet-stream") : .json([:]) }
        }
        let image = try await makeClient(server).fetchBytes("/file-read-34105.png")
        XCTAssertEqual(image, png)
        XCTAssertTrue(ZenTaoClient.isImage(png))
    }

    func testALoginPageOrARedirectIsNeverAnImage() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                if req.path.contains("file-read-7") { return .html("<html><body>Please log in</body></html>") }
                if req.path.contains("file-read-8") { return .bytes(Data("<html>login</html>".utf8), contentType: "application/octet-stream") }
                return .redirect(to: "/user-login.html")
            }
        }
        let client = makeClient(server)
        let html = try await client.fetchBytes("/file-read-7.png")
        let disguised = try await client.fetchBytes("/file-read-8.png")
        let moved = try await client.fetchBytes("/file-read-9.png")
        XCTAssertNil(html)
        XCTAssertNil(disguised)   // not a picture whatever its type says
        XCTAssertNil(moved)
        XCTAssertFalse(ZenTaoClient.isImage(Data("<html>login</html>".utf8)))
    }

    func testDownloadBytesRecoversFromADeadSessionWithAFreshLogin() async throws {
        var logins = 0
        let server = StubServer { req in
            if req.path.hasSuffix("/tokens") { logins += 1; return .json(["token": "tok\(logins)"]) }
            // The asset channel only knows the second session; the first is bounced to the login page.
            return req.query("zentaosid") == "tok2" ? .bytes(Data("PDF".utf8), contentType: "application/pdf") : .redirect(to: "/user-login.html")
        }
        let data = try await makeClient(server).downloadBytes("/file-download-3.pdf")
        XCTAssertEqual(data, Data("PDF".utf8))
        XCTAssertEqual(logins, 2)
        // Same-session retry first, then the fresh login.
        XCTAssertEqual(server.requests.filter { $0.path.contains("file-download-3") }.count, 3)
    }

    func testOffServerAssetsGetNoSessionAndNoRetry() async throws {
        let server = StubServer { req in req.url.host == "cdn.example.org" ? .html("nope", status: 404) : .json(["token": "t"]) }
        let data = try await makeClient(server).downloadBytes("https://cdn.example.org/a.png")
        XCTAssertNil(data)
        let req = try XCTUnwrap(server.requests.first { $0.url.host == "cdn.example.org" })
        XCTAssertNil(req.header("Token"))
        XCTAssertNil(req.query("zentaosid"))
        XCTAssertEqual(server.requests.filter { $0.url.host == "cdn.example.org" }.count, 1)
    }

    // MARK: Messages, user info, docs

    func testMessagesReadsTheClassicDropmenuView() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                req.path.contains("message-ajaxGetDropmenu-all") ? .json(wrapped(["allMessages": ["2026-10-09": [Any]()]])) : .json([:])
            }
        }
        let reply = try await makeAdapter(server).fetchMessages().get()
        XCTAssertNotNil(reply.json["allMessages"])
        let req = try XCTUnwrap(server.requests.first { $0.path.contains("message-") })
        XCTAssertEqual(req.header("Cookie"), "zentaosid=t; lang=en")
    }

    func testMessagesFailsOnAReplyWithoutAMessageList() async throws {
        let server = StubServer { req in .tokenOr(req) { .html("<html>login</html>") } }
        let res = await makeAdapter(server).fetchMessages()
        XCTAssertNotNil(res.failure)
    }

    func testMessageActionFailsOnANon200() async throws {
        let server = StubServer { req in .tokenOr(req) { req.path.contains("ajaxDelete-12") ? .text("", status: 404) : .text("") } }
        let adapter = makeAdapter(server)
        let ok = await adapter.messageAction("ajaxMarkRead-all")
        XCTAssertNotNil(ok.value)
        let bad = await adapter.messageAction("ajaxDelete-12")
        XCTAssertNotNil(bad.failure)
    }

    func testFetchUserInfoRejectsAnErrorBodyWithNoProfile() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                req.query("fields") == "bad" ? .json(["error": "denied"], status: 403)
                    : .json(["profile": ["account": "me"], "task": ["total": 1]])
            }
        }
        let adapter = makeAdapter(server)
        let good = try await adapter.fetchUserInfo(fields: "task", limit: 8).get()
        XCTAssertNotNil(asMap(good.json["profile"]))
        let bad = await adapter.fetchUserInfo(fields: "bad", limit: 8)
        XCTAssertNotNil(bad.failure)
    }

    func testDocsRemoteReadsTheV1DocEndpointsAndTheClassicHistory() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                if req.path.hasSuffix("/api.php/v1/doclibs") { return .json(["libs": [["id": 1, "name": "A"]]]) }
                if req.path.hasSuffix("/api.php/v1/docs") { return .json(["docs": [["id": 5, "title": "T"]]]) }
                if req.path.contains("action-ajaxGetList-doc-5") { return .json(wrapped([["id": 1, "action": "edited"] as JSON])) }
                return .json([:])
            }
        }
        let remote = ZenTaoDocsRemote(client: makeClient(server))
        let libs = try await remote.libs()
        XCTAssertEqual(mapZenTaoDocLibs(libs).map(\.name), ["A"])
        let docs = try await remote.docs("1")
        XCTAssertEqual(mapZenTaoDocSummaries(docs, libId: "1").map(\.title), ["T"])
        XCTAssertEqual(server.requests.first { $0.path.hasSuffix("/docs") }?.query("lib"), "1")
        let history = try await remote.history("5")
        XCTAssertEqual((history["actions"] as? [Any])?.count, 1)
    }
}
