import CoreDomain
import Foundation
@testable import FeatureChat

let fakeToken = "0123456789abcdef0123456789abcdef"

/// `serverInfo`/HTTP stand-in: returns queued results then `fallback`.
final class FakeXxdHttp: XxdHttpClient, @unchecked Sendable {
    let clientVersion = "9.1.2", lang = "en", device = "desktop"
    var fallback: Outcome<XxdServerInfo>
    var queued: [Outcome<XxdServerInfo>] = []
    private(set) var calls = 0
    var downloads: [URL] = []
    var downloadBytes = Data([1, 2, 3])
    var uploadResult: Outcome<(id: Int, time: Int)> = .success((id: 7, time: 1_700_000_000_000))
    var uploads: [(chatGid: String, fileName: String, size: Int)] = []
    private let lock = NSLock()

    init(_ fallback: Outcome<XxdServerInfo>) { self.fallback = fallback }

    func fetchServerInfo(_ c: XxdCredentials) async -> Outcome<XxdServerInfo> {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        return queued.isEmpty ? fallback : queued.removeFirst()
    }

    func download(_ url: URL, pinnedFingerprint: String?, onProgress: (@Sendable (Int, Int?) -> Void)?, cancel: ChatCancelToken?) async -> Outcome<Data> {
        downloads.append(url)
        onProgress?(downloadBytes.count, downloadBytes.count)
        return .success(downloadBytes)
    }

    func upload(server: URL, token: String, userId: Int, chatGid: String, fileName: String, bytes: Data, mimeType: String?,
                serverName: String, pinnedFingerprint: String?, onProgress: (@Sendable (Double) -> Void)?,
                cancel: ChatCancelToken?) async -> Outcome<(id: Int, time: Int)> {
        uploads.append((chatGid, fileName, bytes.count))
        onProgress?(1)
        return uploadResult
    }

    func fileDownloadURL(server: URL, userId: Int, sessionId: String, fileId: Int, fileName: String, fileTime: Int,
                         serverName: String, thumbnail: Bool, preview: Bool) -> URL {
        XxdHttpDatasource().fileDownloadURL(server: server, userId: userId, sessionId: sessionId, fileId: fileId,
                                            fileName: fileName, fileTime: fileTime, serverName: serverName,
                                            thumbnail: thumbnail, preview: preview)
    }
}

func serverInfoOk(scheme: JSONObject? = nil) -> Outcome<XxdServerInfo> {
    var info = XxdServerInfo(token: fakeToken, chatPort: 11444, version: "v9.2.2", enableClientAes: scheme != nil)
    info.apiScheme = scheme
    return .success(info)
}

let offlineInfo: Outcome<XxdServerInfo> = .failure(.network("offline"))

/// In-memory xxd: speaks plain JSON, or packed + AES when given a scheme.
final class FakeXxdServer: @unchecked Sendable {
    let scheme: JSONObject?
    private let lock = NSLock()
    private(set) var sockets: [FakeXxdSocket] = []
    private(set) var requests: [JSONObject] = []
    var rejectLogin = false
    /// Pushed as `chatgetlist` right after a successful login.
    var chats: [JSONValue] = []
    /// Replies to methods other than login/ping; return nil to stay silent.
    var onRequest: (@Sendable (JSONObject) -> JSONObject?)?

    init(scheme: JSONObject? = nil) { self.scheme = scheme }

    var current: FakeXxdSocket { lock.lock(); defer { lock.unlock() }; return sockets.last! }
    func requests(_ method: String) -> [JSONObject] { requests.filter { $0["method"]?.string == method } }

    var connector: XxdSocketConnector {
        { [self] _, _ in
            let s = FakeXxdSocket(self)
            lock.lock(); sockets.append(s); lock.unlock()
            return s
        }
    }

    fileprivate func handle(_ socket: FakeXxdSocket, _ req: JSONObject) {
        lock.lock(); requests.append(req); lock.unlock()
        let rid = req["rid"] ?? .null
        switch req["method"]?.string {
        case "userlogin":
            if rejectLogin {
                socket.push(["method": "userlogin", "rid": rid, "result": "fail", "message": "bad password"]); return
            }
            socket.push(["method": "userlogin", "rid": rid, "result": "success",
                         "data": ["id": 40, "account": "demo", "realname": "Demo"]])
            socket.push(["method": "chatgetlist", "rid": rid, "result": "success", "data": .array(chats)])
            socket.push(["method": "syssessionid", "result": "success", "data": "session-1"])
        case "ping": break
        default:
            if let reply = onRequest?(req) { socket.push(reply) }
        }
    }
}

final class FakeXxdSocket: XxdSocket, @unchecked Sendable {
    let server: FakeXxdServer
    private let codec: ApiSchemeCodec?
    private let cipher: XxdCipher?
    private var cont: AsyncThrowingStream<XxdFrame, Error>.Continuation!
    let frames: AsyncThrowingStream<XxdFrame, Error>
    private(set) var closed = false

    init(_ server: FakeXxdServer) {
        self.server = server
        codec = server.scheme.map { ApiSchemeCodec($0) }
        cipher = server.scheme == nil ? nil : try! XxdCipher(token: fakeToken)
        var c: AsyncThrowingStream<XxdFrame, Error>.Continuation!
        frames = AsyncThrowingStream { c = $0 }
        cont = c
    }

    func send(_ frame: XxdFrame) async throws {
        let text: String
        switch frame {
        case .text(let s): text = s
        case .binary(let d): text = try cipher!.decrypt(d)
        }
        let json = try JSONValue.parse(text)
        let req: JSONValue = (codec != nil && json.array != nil) ? try codec!.decode(json, fallback: "requestPack") : json
        server.handle(self, req.object!)
    }

    /// Server → client packet.
    func push(_ packet: JSONObject) {
        if closed { return }
        guard let codec else { cont.yield(.text(JSONValue.object(packet).serialized())); return }
        let packed = try! codec.encodeToJson("\(packet["method"]!.string!)Response", .object(packet), fallback: "responsePack")
        cont.yield(.binary(cipher!.encrypt(packed)))
    }


    /// Simulates the server or network dropping the connection.
    func drop() { closed = true; cont.finish() }
    func close(code: Int?, reason: String?) async { if !closed { drop() } }
    var closeCode: Int? { closed ? 1006 : nil }
    var closeReason: String? { nil }
}
