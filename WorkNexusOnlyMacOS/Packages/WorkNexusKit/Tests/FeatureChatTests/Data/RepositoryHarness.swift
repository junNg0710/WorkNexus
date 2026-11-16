import CoreDomain
import CorePersistence
import GRDB
import XCTest
@testable import FeatureChat

let acc = "acc"
let t0Server = 1_791_345_529

func serverMessage(_ id: Int, cgid: String = "g1", user: Int = 31, content: String = "hi", type: String = "plain") -> JSONValue {
    ["gid": .string("m\(id)"), "cgid": .string(cgid), "id": .int(id), "index": .int(id), "user": .int(user), "date": .int(t0Server + id),
     "content": .string(content), "contentType": .string(type), "type": "normal", "deleted": false]
}

/// An in-memory database, a fake xxd server with 120 messages of history, and a repository wired to them.
class RepositoryTestCase: XCTestCase {
    var db: AppDatabase!
    var server: FakeXxdServer!
    var http: FakeXxdHttp!
    var store: InMemoryCredentialStore!
    var repo: XxdChatRepository!
    var filesDir: URL!
    var opened = Locked<[XxdCredentials]>([])
    let history = Locked<[Int: JSONValue]>([:])
    let nextId = Locked(1000)
    let now = Date(timeIntervalSince1970: 1_791_400_000)

    override func setUp() async throws {
        db = try AppDatabase.inMemory(registrars: [ChatMigrations.registrar])
        try await db.writer.write { d in
            try d.execute(sql: "INSERT INTO accounts (id, workspaceId, providerType, handle, baseUrl, credentialsRef) VALUES ('acc','ws','zentao','demo','https://zt.test:4433/zentao','secret:acc')")
        }
        store = InMemoryCredentialStore()
        _ = await store.write("secret:acc", value: "pw")
        server = FakeXxdServer()
        server.chats = [
            ["gid": "g1", "type": "group", "name": "Team", "lastActiveTime": .int(t0Server + 100), "lastMessage": 100, "lastReadMessageIndex": 99,
             "lastMessageInfo": serverMessage(100, content: "hello")],
            ["gid": "31&40", "type": "one2one", "name": "", "lastActiveTime": .int(t0Server), "lastMessage": 0, "lastReadMessageIndex": 0],
        ]
        history.with { h in h = Dictionary(uniqueKeysWithValues: (1...120).map { ($0, serverMessage($0)) }) }
        let history = history, nextId = nextId
        server.onRequest = { req in
            let params = req["params"]?.array ?? []
            let data: JSONValue?
            switch req["method"]?.string {
            case "usergetlist": data = .array((params.first?.array ?? []).map { ["id": $0, "account": .string("u\(JS.toString($0))"), "realname": .string("User \(JS.toString($0))")] })
            case "chatgetbygid": data = ["gid": params[0], "type": "group", "name": "New chat", "lastActiveTime": .int(t0Server + 500)]
            case "messagesend":
                data = .array((params.first?.array ?? []).map { m in
                    var o = m.object!; o["id"] = .int(nextId.with { $0 += 1; return $0 }); o["date"] = .int(t0Server + 900); return .object(o)
                })
            case "chatstar": data = ["gid": params[1], "star": params[0]]
            case "userupdate": var o = params[0].object!; o["id"] = 40; data = .object(o)
            case "chatgetmessageinfo": data = ["lastMessage": 120, "messageCount": 120]
            case "chatsetlastreadmessagebyindex": data = ["gid": params[0], "id": params[1]]
            case "messagesync":
                let start = params[1].intValue!
                if params[2] == .bool(false) { data = .array((start..<start + 50).compactMap { history.current[$0] }) }
                else { data = .array(stride(from: start, to: max(0, start - 50), by: -1).filter { $0 > 0 }.compactMap { history.current[$0] }) }
            case "messagegetlist": data = .array((params[1].array ?? []).compactMap { history.current[$0.intValue!] })
            default: data = nil
            }
            guard let data else { return nil }
            return ["method": req["method"] ?? .null, "rid": req["rid"] ?? .null, "result": "success", "data": data]
        }
        http = FakeXxdHttp(serverInfoOk())
        filesDir = FileManager.default.temporaryDirectory.appendingPathComponent("wn_chat_files_\(UUID().uuidString)")
        let server = server!, http = http!, opened = opened
        repo = XxdChatRepository(db: db, credentials: store, http: http, files: ChatFileCache(root: filesDir),
                                 connection: { c in
                                     opened.with { $0.append(c) }
                                     return XxdConnection(credentials: c, http: http, connector: server.connector, pingInterval: 300, requestTimeout: 1, backoff: { _ in 0.01 })
                                 }, now: { [now] in now })
    }

    override func tearDown() async throws {
        await repo.disconnect(accountId: acc)
        try? FileManager.default.removeItem(at: filesDir)
    }

    /// The first value of `stream` satisfying `done` (fails after 3 s).
    func eventually<T: Sendable>(_ stream: AsyncStream<T>, file: StaticString = #filePath, line: UInt = #line, _ done: @escaping @Sendable (T) -> Bool) async throws -> T {
        try await withThrowingTaskGroup(of: T?.self) { g in
            g.addTask { for await v in stream where done(v) { return v }; return nil }
            g.addTask { try await Task.sleep(nanoseconds: 3_000_000_000); return nil }
            let first = try await g.next()!
            g.cancelAll()
            return try XCTUnwrap(first, "timed out waiting for the stream", file: file, line: line)
        }
    }

    func byGid(_ list: [ChatConversation], _ gid: String) -> ChatConversation? { list.first { $0.gid == gid } }
    func connectAndWait() async throws {
        _ = await repo.connect(accountId: acc)
        _ = try await eventually(repo.watchConversations(accountId: acc)) { $0.count == 2 }
    }
}
