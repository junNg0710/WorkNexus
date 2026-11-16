import CoreDomain
import XCTest
@testable import FeatureChat

/// Port of test/data/chat/xxd_connection_test.dart against a fake socket.
final class XxdConnectionTests: XCTestCase {
    let credentials = XxdCredentials(server: URL(string: "https://chat.test:11443")!, account: "demo", password: "secret")
    var server = FakeXxdServer()
    var http = FakeXxdHttp(serverInfoOk())
    var connection: XxdConnection!

    override func setUp() { server = FakeXxdServer(); http = FakeXxdHttp(serverInfoOk()) }
    override func tearDown() async throws { await connection?.dispose() }

    @discardableResult
    private func connect(ping: TimeInterval = 300, timeout: TimeInterval = 2) -> XxdConnection {
        connection = XxdConnection(credentials: credentials, http: http, connector: server.connector,
                                   pingInterval: ping, requestTimeout: timeout, backoff: { _ in 0.01 })
        return connection
    }

    private func waitForState(_ pred: @escaping @Sendable (XxdConnectionState) -> Bool) async throws -> XxdConnectionState {
        let stream = connection.states
        return try await withThrowingTaskGroup(of: XxdConnectionState?.self) { g in
            g.addTask { for await s in stream where pred(s) { return s }; return nil }
            g.addTask { try await Task.sleep(nanoseconds: 3_000_000_000); return nil }
            let first = try await g.next()!
            g.cancelAll()
            return try XCTUnwrap(first, "timed out waiting for state")
        }
    }

    func testLoginKeepsPushesAndPicksUpSessionId() async throws {
        connect()
        let stream = connection.packets
        let collector = Task { () -> [String] in
            var seen: [String] = []
            for await p in stream { seen.append(p.apiName); if seen.count == 3 { break } }
            return seen
        }
        let r = await connection.start()
        XCTAssertEqual(r.value?.userId, 40)
        let login = server.requests.first!
        XCTAssertEqual(login["method"], "userlogin")
        XCTAssertEqual(login["params"], ["", "demo", .string(XxdSigning.passwordAuthKey("secret")), ["status": "online", "simple": false]])
        XCTAssertEqual(login["rid"], "login_desktop_demo")
        let seen = await collector.value
        XCTAssertEqual(seen, ["userlogin", "chatgetlist", "syssessionid"])
        let state = try await waitForState { $0.session?.sessionId == "session-1" }
        XCTAssertEqual(state.session?.sessionId, "session-1")
    }

    func testRepliesMatchByRidOrByMethod() async throws {
        server.onRequest = { req in
            var o = JSONObject([("method", req["method"]!)])
            if req["method"] == "chatgetmessageinfo" { o["rid"] = req["rid"] }
            o["result"] = "success"; o["data"] = ["echo": req["params"] ?? .null]
            return o
        }
        connect(); _ = await connection.start()
        let byRid = await connection.request(XxdRequest("chatGetMessageInfo", params: ["g1"]))
        let byMethod = await connection.request(XxdRequest("messageSync", params: ["g1", 5, true, 10, false]))
        XCTAssertEqual(byRid.value?.data?["echo"], ["g1"])
        XCTAssertEqual(byMethod.value?.data?["echo"], ["g1", 5, true, 10, false])
        XCTAssertEqual(server.requests.last?["userID"], 40)
        XCTAssertFalse(server.requests.last?["rid"]?.string?.isEmpty ?? true)
    }

    func testFailedReplyBecomesFailureWithServerMessage() async {
        server.onRequest = { req in ["method": req["method"]!, "rid": req["rid"]!, "result": "fail", "message": "no permission"] }
        connect(); _ = await connection.start()
        let r = await connection.request(XxdRequest("chatCreate"))
        XCTAssertEqual(r.failure, .unexpected("no permission"))
    }

    func testSilentServerTimesOut() async {
        connect(timeout: 0.05); _ = await connection.start()
        let r = await connection.request(XxdRequest("chatGetList"))
        guard case .network? = r.failure else { return XCTFail("expected network failure, got \(String(describing: r.failure))") }
    }

    func testRejectedLoginStopsWithoutRetrying() async throws {
        server.rejectLogin = true
        connect()
        let r = await connection.start()
        guard case .auth? = r.failure else { return XCTFail() }
        guard case .stopped = await connection.currentState else { return XCTFail() }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(http.calls, 1)
    }

    func testOfflineStartKeepsRetrying() async throws {
        http.queued = [offlineInfo, offlineInfo]
        connect()
        let first = await connection.start()
        guard case .network? = first.failure else { return XCTFail() }
        guard case .reconnecting = await connection.currentState else { return XCTFail() }
        _ = try await waitForState { $0.isOnline }
        XCTAssertEqual(http.calls, 3)
    }

    func testDroppedSocketReconnectsWithFreshHandshake() async throws {
        connect(); _ = await connection.start()
        server.current.drop()
        _ = try await waitForState { if case .reconnecting = $0 { true } else { false } }
        let online = try await waitForState { $0.isOnline }
        XCTAssertEqual(online.session?.userId, 40)
        XCTAssertEqual(server.sockets.count, 2)
        XCTAssertEqual(http.calls, 2)
        XCTAssertEqual(server.requests("userlogin").count, 2)
    }

    func testKickoffStopsForGood() async throws {
        connect(); _ = await connection.start()
        server.current.push(["method": "userkickoff", "reason": "login elsewhere"])
        let st = try await waitForState { if case .stopped = $0 { true } else { false } }
        guard case .stopped(let f, let kicked) = st else { return XCTFail() }
        XCTAssertTrue(kicked)
        guard case .auth = f else { return XCTFail() }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(server.sockets.count, 1)
    }

    func testPingsAndWatchdogReconnects() async throws {
        connect(ping: 0.04); _ = await connection.start()
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertFalse(server.requests("ping").isEmpty)
        _ = try await waitForState { if case .reconnecting = $0 { true } else { false } }
        XCTAssertTrue(server.sockets[0].closed)
    }

    func testStopFailsPendingAndDoesNotReconnect() async throws {
        connect(); _ = await connection.start()
        async let pending = connection.request(XxdRequest("chatGetList"))
        try await Task.sleep(nanoseconds: 30_000_000)
        await connection.stop()
        guard case .network? = await pending.failure else { return XCTFail() }
        guard case .disconnected = await connection.currentState else { return XCTFail() }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(server.sockets.count, 1)
    }

    func testEndToEndWithRealSchemeAndAES() async throws {
        let scheme = try Fixtures.json("api_scheme.json").object!
        server = FakeXxdServer(scheme: scheme)
        http = FakeXxdHttp(serverInfoOk(scheme: scheme))
        server.onRequest = { req in
            ["method": req["method"]!, "rid": req["rid"]!, "result": "success", "data": ["lastMessage": 195017, "messageCount": 1097]]
        }
        connect()
        let login = await connection.start()
        let info = await connection.request(XxdRequest("chatGetMessageInfo", params: ["g1"]))
        XCTAssertEqual(login.value?.userId, 40)
        XCTAssertEqual(info.value?.data, ["lastMessage": 195017, "messageCount": 1097])
    }

    func testOfflineRequestFailsInsteadOfThrowing() async {
        connect()
        let r = await connection.request(XxdRequest("chatGetList"))
        XCTAssertNotNil(r.failure)
    }

    func testBackoffCapsAtSixtySeconds() {
        XCTAssertEqual([1, 2, 3, 4, 7, 8, 20].map(defaultXxdBackoff), [1, 2, 4, 8, 60, 60, 60])
    }
}
