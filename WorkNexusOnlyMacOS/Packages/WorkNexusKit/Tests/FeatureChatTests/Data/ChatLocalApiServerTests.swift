import CoreDomain
import Foundation
import XCTest
@testable import FeatureChat

/// What the fake handlers saw and will answer.
final class LocalApiCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [[String: AnyHashable]] = [], _calls: [[String: AnyHashable]] = []
    var sendResult: Outcome<Void> = .success(())
    var step: Outcome<ChatHistoryStep> = .success(ChatHistoryStep(loaded: 0, reachesStart: true))
    var file: Outcome<ChatAttachmentFile> = .failure(.notFound("none"))
    var sent: [[String: AnyHashable]] { lock.withLock { _sent } }
    var calls: [[String: AnyHashable]] { lock.withLock { _calls } }
    func record(sent value: [String: AnyHashable]) { lock.withLock { _sent.append(value) } }
    func record(call value: [String: AnyHashable]) { lock.withLock { _calls.append(value) } }

    var handlers: ChatLocalApiHandlers {
        ChatLocalApiHandlers(
            send: { [self] a, g, t, md in record(sent: ["accountId": a, "chatGid": g, "text": t, "markdown": md]); return sendResult },
            loadOlder: { [self] a, g, n in record(call: ["accountId": a, "chatGid": g, "pageSize": n]); return step },
            attachment: { [self] a, g, id in record(call: ["accountId": a, "chatGid": g, "messageId": id]); return file })
    }
}

/// The localhost endpoint local AI tools use chat through: only with the token from the discovery file, never from a
/// browser, and only while running. Runs on an ephemeral loopback port with fake handlers.
/// Ported from: test/data/chat/chat_local_api_server_test.dart
final class ChatLocalApiServerTests: XCTestCase {
    private var dir: URL!
    private var server: ChatLocalApiServer!
    private var fake: LocalApiCalls!
    private let session = URLSession(configuration: .ephemeral)

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("wn_local_api_\(UUID().uuidString)")
        fake = LocalApiCalls()
        server = ChatLocalApiServer(directory: dir)
        let started = await server.start(fake.handlers)
        XCTAssertNotNil(started.value, "\(String(describing: started.failure))")
    }

    override func tearDown() async throws {
        _ = await server.stop()
        try? FileManager.default.removeItem(at: dir)
    }

    private var discovery: URL { dir.appendingPathComponent(ChatLocalApiServer.discoveryFileName) }

    private func readDiscovery() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: discovery)) as? [String: Any])
    }

    private func token() throws -> String { try XCTUnwrap(readDiscovery()["token"] as? String) }

    private func call(_ method: String, _ path: String, token: String? = nil, body: Any? = nil,
                      headers: [String: String] = [:]) async throws -> (Int, [String: Any]) {
        let port = try XCTUnwrap(readDiscovery()["port"] as? Int)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        if let body {
            if let text = body as? String { request.httpBody = Data(text.utf8) } else { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        }
        let (data, response) = try await session.data(for: request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, json)
    }

    func testWritesItsPortAndATokenOnlyTheUserCanRead() throws {
        let info = try readDiscovery()
        XCTAssertEqual(info["version"] as? Int, 1)
        XCTAssertNotNil(info["port"] as? Int)
        XCTAssertEqual(info["pid"] as? Int, Int(ProcessInfo.processInfo.processIdentifier))
        XCTAssertGreaterThanOrEqual(try token().count, 40)
        let mode = try FileManager.default.attributesOfItem(atPath: discovery.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    func testSendsAMessageWithTheRightToken() async throws {
        let (status, body) = try await call("POST", "/v1/chat/send", token: try token(), body: ["accountId": "zt-1", "chatGid": "40&40", "text": "hi"])
        XCTAssertEqual(status, 200)
        XCTAssertEqual(body as NSDictionary, ["ok": true])
        XCTAssertEqual(fake.sent, [["accountId": "zt-1", "chatGid": "40&40", "text": "hi", "markdown": false]])
    }

    func testPassesOnASendFailureAs502WithItsMessage() async throws {
        fake.sendResult = .failure(.network("Chat is offline"))
        let (status, body) = try await call("POST", "/v1/chat/send", token: try token(),
                                            body: ["accountId": "a", "chatGid": "g", "text": "t", "markdown": true])
        XCTAssertEqual(status, 502)
        XCTAssertEqual(body["error"] as? String, "Chat is offline")
        XCTAssertEqual(fake.sent.first?["markdown"], true)
    }

    func testRefusesAMissingOrWrongToken() async throws {
        let payload = ["accountId": "a", "chatGid": "g", "text": "t"]
        let v1 = try await call("POST", "/v1/chat/send", body: payload).0
        XCTAssertEqual(v1, 401)
        let v2 = try await call("POST", "/v1/chat/send", token: "nope", body: payload).0
        XCTAssertEqual(v2, 401)
        XCTAssertTrue(fake.sent.isEmpty)
    }

    func testRefusesBrowserRequestsEvenWithTheToken() async throws {
        let (status, _) = try await call("POST", "/v1/chat/send", token: try token(), body: ["accountId": "a", "chatGid": "g", "text": "t"],
                                         headers: ["Origin": "https://example.com"])
        XCTAssertEqual(status, 403)
        XCTAssertTrue(fake.sent.isEmpty)
    }

    func testRejectsMalformedOversizedAndUnknownRequests() async throws {
        let token = try token()
        let v3 = try await call("POST", "/v1/chat/send", token: token, body: "{oops").0
        XCTAssertEqual(v3, 400)
        let v4 = try await call("POST", "/v1/chat/send", token: token, body: ["chatGid": "g", "text": "t"]).0
        XCTAssertEqual(v4, 400)
        let big = String(repeating: "x", count: 70_000)
        let v5 = try await call("POST", "/v1/chat/send", token: token, body: ["accountId": "a", "chatGid": "g", "text": big]).0
        XCTAssertEqual(v5, 413)
        let v6 = try await call("GET", "/v1/chat/send", token: token).0
        XCTAssertEqual(v6, 404)
        let v7 = try await call("GET", "/v1/health", token: token).0
        XCTAssertEqual(v7, 200)
        XCTAssertTrue(fake.sent.isEmpty)
    }

    func testStoppingRemovesTheDiscoveryFileAndARestartGetsANewToken() async throws {
        let first = try token()
        _ = await server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: discovery.path))
        let v8 = (await server.start(fake.handlers)).value
        XCTAssertNotNil(v8)
        XCTAssertNotEqual(try token(), first)
    }

    func testLoadsOneOlderPageOf100MessagesUnlessAsked() async throws {
        let token = try token()
        fake.step = .success(ChatHistoryStep(loaded: 80, reachesStart: false))
        let (status, body) = try await call("POST", "/v1/chat/load-older", token: token, body: ["accountId": "a", "chatGid": "g"])
        XCTAssertEqual(status, 200)
        XCTAssertEqual(body as NSDictionary, ["ok": true, "loaded": 80, "reachesStart": false])
        XCTAssertEqual(fake.calls, [["accountId": "a", "chatGid": "g", "pageSize": 100]])
        let v9 = try await call("POST", "/v1/chat/load-older", token: token, body: ["accountId": "a", "chatGid": "g", "pageSize": 0]).0
        XCTAssertEqual(v9, 400)
        let v10 = try await call("POST", "/v1/chat/load-older", token: token, body: ["accountId": "a", "chatGid": "g", "pageSize": 2.5]).0
        XCTAssertEqual(v10, 400)
    }

    func testReturnsWhereAnAttachmentWasDownloadedTo() async throws {
        fake.file = .success(ChatAttachmentFile(path: "/cache/a.png", name: "a.png", size: 12, mimeType: "image/png", isImage: true))
        let (status, body) = try await call("POST", "/v1/chat/attachment", token: try token(), body: ["accountId": "a", "chatGid": "g", "messageId": 7])
        XCTAssertEqual(status, 200)
        XCTAssertEqual(body as NSDictionary, ["ok": true, "path": "/cache/a.png", "name": "a.png", "size": 12, "mimeType": "image/png", "isImage": true])
        XCTAssertEqual(fake.calls.first?["messageId"], 7)
    }

    func testMapsAttachmentFailuresTo404And400And502() async throws {
        let token = try token()
        func status() async throws -> Int {
            try await call("POST", "/v1/chat/attachment", token: token, body: ["accountId": "a", "chatGid": "g", "messageId": 7]).0
        }
        fake.file = .failure(.notFound("gone"));
        let v11 = try await status()
        XCTAssertEqual(v11, 404)
        fake.file = .failure(.validation("no file"));
        let v12 = try await status()
        XCTAssertEqual(v12, 400)
        fake.file = .failure(.network("offline"));
        let v13 = try await status()
        XCTAssertEqual(v13, 502)
        let v14 = try await call("POST", "/v1/chat/attachment", token: token, body: ["accountId": "a", "chatGid": "g", "messageId": "7"]).0
        XCTAssertEqual(v14, 400)
        let v15 = try await call("POST", "/v1/chat/attachment", token: token, body: ["accountId": "a", "chatGid": "g", "messageId": true]).0
        XCTAssertEqual(v15, 400)
    }

    func testListensOnLoopbackOnly() async throws {
        let port = try XCTUnwrap(readDiscovery()["port"] as? Int)
        let v16 = await server.port.map(Int.init)
        XCTAssertEqual(v16, port)
        XCTAssertTrue(ChatLocalApiServer.isLoopback(.ipv4(.loopback)))
        XCTAssertFalse(ChatLocalApiServer.isLoopback(.ipv4(.init("192.168.1.2")!)))
    }
}

/// The HTTP request reader on its own: split bodies, oversized bodies drained, malformed heads.
final class LocalHttpRequestReaderTests: XCTestCase {
    func testReadsARequestArrivingInPieces() {
        var reader = LocalHttpRequestReader()
        XCTAssertEqual(reader.feed(Data("POST /v1/chat/send?x=1 HTTP/1.1\r\nContent-Le".utf8)), .needMore)
        XCTAssertEqual(reader.feed(Data("ngth: 4\r\nAuthorization: Bearer t\r\n\r\n{\"".utf8)), .needMore)
        XCTAssertEqual(reader.feed(Data("a}".utf8)),
                       .done(LocalHttpRequest(method: "POST", path: "/v1/chat/send", headers: ["content-length": "4", "authorization": "Bearer t"],
                                              body: Data("{\"a}".utf8))))
    }

    func testDrainsAnOversizedBodyBeforeAnswering() {
        var reader = LocalHttpRequestReader(maxBodyBytes: 4)
        XCTAssertEqual(reader.feed(Data("POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\n12345".utf8)), .needMore)
        guard case .done(let r) = reader.feed(Data("67890".utf8)) else { return XCTFail("not done") }
        XCTAssertNil(r.body)
    }

    func testRefusesChunkedBodiesAndBadHeads() {
        var chunked = LocalHttpRequestReader()
        XCTAssertEqual(chunked.feed(Data("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)), .malformed("Chunked bodies are not supported"))
        var bad = LocalHttpRequestReader()
        XCTAssertEqual(bad.feed(Data("HELLO\r\n\r\n".utf8)), .malformed("Bad request line"))
        var huge = LocalHttpRequestReader(maxHeaderBytes: 8)
        XCTAssertEqual(huge.feed(Data("GET / HTTP/1.1\r\nX: yyyyyyyy".utf8)), .malformed("Headers too large"))
    }
}
