import CoreDomain
import CorePersistence
import Foundation
import GRDB
import XCTest
@testable import FeatureChat

/// The MCP server this app ships (`App/Resources/Mcp/worknexus-mcp.mjs`, unchanged from the Flutter app) run for real over
/// stdio against a native database file and the native local chat API with fake handlers — no chat server, no TBChat, no
/// real data. In the spirit of mcp/scripts/mcp-smoke.mjs, with a dependency-free JSON-RPC driver. Skipped without
/// Node.js 22.13+ on `PATH`.
final class McpServerSmokeTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("wn_mcp_smoke_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private var script: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Resources/Mcp/worknexus-mcp.mjs")
    }

    private func seed(_ db: AppDatabase) async throws {
        let t0 = Date(timeIntervalSince1970: 1_791_000_000)
        try await db.writer.write { d in
            try d.execute(sql: "INSERT INTO accounts (id, workspaceId, providerType, handle, baseUrl) VALUES ('acc','ws','zentao','demo','https://zt.test/zentao')")
            try d.execute(sql: "INSERT INTO chatAccounts (accountId, serverUrl, userId) VALUES ('acc','https://zt.test:11443',40)")
            try d.execute(sql: "INSERT INTO chatUsers (accountId, userId, account, realname) VALUES ('acc',40,'me','Me'), ('acc',31,'duong','Đường Văn A')")
            try d.execute(sql: "INSERT INTO chatConversations (accountId, gid, type, name, lastActiveAt) VALUES ('acc','g1','group','Team',?), ('acc','31&40','one2one','',?)",
                          arguments: [t0.addingTimeInterval(60), t0])
            let file = #"{"id":9,"name":"notes.txt","size":11,"time":1}"#
            for (id, sender, type, content, folded) in [(5, 31, "plain", "hello team", "hello team"), (6, 40, "file", file, nil),
                                                         (7, 40, "plain", "Chào Đường", "chao duong")] as [(Int, Int, String, String, String?)] {
                try d.execute(sql: """
                    INSERT INTO chatMessages (accountId, gid, cgid, serverId, messageIndex, senderId, sentAt, contentType, content, searchText)
                    VALUES ('acc', ?, 'g1', ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: ["m\(id)", id, id, sender, t0.addingTimeInterval(Double(id)), type, content, folded])
            }
        }
    }

    func testTheShippedServerReadsTheNativeDatabaseAndUsesTheLocalApi() async throws {
        guard FileManager.default.fileExists(atPath: script.path) else { throw XCTSkip("no bundled MCP server at \(script.path)") }
        guard McpSetup.supports(await NodeRuntimeProbe.runProcess("/usr/bin/env", ["node", "--version"])?.trimmingCharacters(in: .whitespacesAndNewlines))
        else { throw XCTSkip("Node.js 22.13+ is not on PATH") }

        let dbFile = dir.appendingPathComponent("worknexus.sqlite")
        let db = try AppDatabase.open(path: dbFile, registrars: [ChatMigrations.registrar])
        try await seed(db)
        let notes = dir.appendingPathComponent("notes.txt")
        try Data("hello notes".utf8).write(to: notes)
        let fake = LocalApiCalls()
        fake.file = .success(ChatAttachmentFile(path: notes.path, name: "notes.txt", size: 11, mimeType: nil, isImage: false))
        let api = ChatLocalApiServer(directory: dir)
        let v1 = (await api.start(fake.handlers)).value
        XCTAssertNotNil(v1)
        defer { Task { _ = await api.stop() } }

        let driver = dir.appendingPathComponent("driver.mjs")
        try Data(Self.driver.utf8).write(to: driver)
        let output = try await Self.node([driver.path, script.path], env: ["WORKNEXUS_DB": dbFile.path])
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any], output)

        let tools = try XCTUnwrap(result["tools"] as? [String])
        XCTAssertEqual(Set(tools), ["list_conversations", "read_messages", "search_messages", "send_message", "get_attachment"])
        let list = try XCTUnwrap(result["list"] as? [String: Any], "\(result["list"] ?? "")")
        XCTAssertEqual((list["conversations"] as? [[String: Any]])?.compactMap { $0["name"] as? String }, ["Team", "Đường Văn A"])
        XCTAssertEqual(list["account"] as? String, "demo")

        let read = try XCTUnwrap(result["read"] as? [String: Any], "\(result["read"] ?? "")")
        let messages = try XCTUnwrap(read["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.compactMap { $0["id"] as? Int }, [5, 6, 7])
        XCTAssertEqual(messages[1]["attachment"] as? String, "file")
        XCTAssertEqual(messages[2]["from"] as? String, "Me (me)")
        XCTAssertEqual(messages[0]["time"] as? String, "2026-10-03T04:00:05.000Z")
        XCTAssertEqual((read["history"] as? [String: Any])?["reachesStart"] as? Bool, true)
        // 3 stored of 50 asked: one older page of max(50, 50 - 3), and the fake says that reached the start.
        XCTAssertEqual(fake.calls.first, ["accountId": "acc", "chatGid": "g1", "pageSize": 50], "fewer stored than asked: one older page")

        XCTAssertEqual((result["search"] as? [String: Any])?["total"] as? Int, 2, "folded text and the sender's name")
        XCTAssertEqual((result["send"] as? [String: Any])?["sent"] as? Bool, true)
        XCTAssertEqual(fake.sent, [["accountId": "acc", "chatGid": "g1", "text": "hello from smoke", "markdown": false]])
        XCTAssertEqual(result["attachment"] as? [String], ["hello notes"])
    }

    /// Runs `node` with `arguments` (60 s at most); its stdout.
    private static func node(_ arguments: [String], env: [String: String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process(), out = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node"] + arguments
            process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = out
            process.terminationHandler = { _ in
                continuation.resume(returning: String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            }
            do { try process.run() } catch { continuation.resume(throwing: error); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + 60) { if process.isRunning { process.terminate() } }
        }
    }

    /// Talks MCP (newline-delimited JSON-RPC over stdio) to the server at argv[2] and prints what each tool answered.
    private static let driver = #"""
    import { spawn } from 'node:child_process';
    const child = spawn(process.execPath, ['--no-warnings', process.argv[2]], { env: process.env, stdio: ['pipe', 'pipe', 'inherit'] });
    let buffer = '', next = 0;
    const waiting = new Map();
    child.stdout.on('data', (chunk) => {
      buffer += chunk;
      for (let i; (i = buffer.indexOf('\n')) >= 0;) {
        const line = buffer.slice(0, i); buffer = buffer.slice(i + 1);
        if (!line.trim()) continue;
        const msg = JSON.parse(line);
        if (msg.id != null && waiting.has(msg.id)) { waiting.get(msg.id)(msg); waiting.delete(msg.id); }
      }
    });
    const send = (m) => child.stdin.write(JSON.stringify({ jsonrpc: '2.0', ...m }) + '\n');
    const rpc = (method, params) => new Promise((resolve) => { const id = ++next; waiting.set(id, resolve); send({ id, method, params }); });
    const call = async (name, args) => {
      const { result } = await rpc('tools/call', { name, arguments: args });
      if (result.isError) return { error: result.content[0].text };
      return name === 'get_attachment' ? result.content.slice(1).map((c) => c.text) : JSON.parse(result.content[0].text);
    };
    await rpc('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'smoke', version: '0' } });
    send({ method: 'notifications/initialized' });
    const out = { tools: (await rpc('tools/list', {})).result.tools.map((t) => t.name) };
    out.list = await call('list_conversations', { app: 'zentao', limit: 5 });
    out.read = await call('read_messages', { app: 'zentao', conversation: 'Team', limit: 50 });
    out.search = await call('search_messages', { app: 'zentao', query: 'duong', limit: 5 });
    out.send = await call('send_message', { app: 'zentao', conversation: 'Team', text: 'hello from smoke' });
    out.attachment = await call('get_attachment', { app: 'zentao', conversation: 'Team', messageId: 6 });
    console.log(JSON.stringify(out));
    child.kill();
    """#
}
