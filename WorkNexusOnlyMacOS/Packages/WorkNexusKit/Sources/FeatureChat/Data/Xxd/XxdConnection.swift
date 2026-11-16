import CoreDomain
import Foundation

/// 1 s, 2 s, 4 s … capped at 60 s.
public func defaultXxdBackoff(_ attempt: Int) -> TimeInterval {
    min(60, pow(2, Double(max(0, attempt - 1))))
}

/// One reply slot: completes at most once and may complete before anyone waits.
final class XxdReplySlot: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Outcome<XxdResponse>?
    private var cont: CheckedContinuation<Outcome<XxdResponse>, Never>?

    func complete(_ r: Outcome<XxdResponse>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = r
        let c = cont; cont = nil
        lock.unlock()
        c?.resume(returning: r)
    }

    var isCompleted: Bool { lock.lock(); defer { lock.unlock() }; return result != nil }

    func wait() async -> Outcome<XxdResponse> {
        await withCheckedContinuation { (c: CheckedContinuation<Outcome<XxdResponse>, Never>) in
            lock.lock()
            if let r = result { lock.unlock(); c.resume(returning: r) } else { cont = c; lock.unlock() }
        }
    }
}

/// One live xxd chat session: `serverInfo` handshake, socket login, rid-based request/reply matching, keep-alive and
/// reconnection. Every incoming packet (replies included) is published on `packets`; subscribe before `start()` so
/// packets pushed during login (`chatgetlist`, …) are seen.
/// Ported from: lib/features/chat/data/datasources/xxd/xxd_connection.dart
public actor XxdConnection {
    private struct Pending { let rid: String; let apiName: String; let slot: XxdReplySlot }

    public nonisolated let credentials: XxdCredentials
    private let http: any XxdHttpClient
    private let connector: XxdSocketConnector
    private let pingInterval: TimeInterval
    private let requestTimeout: TimeInterval
    private let backoff: @Sendable (Int) -> TimeInterval
    private let log: XxdTrafficLog

    private nonisolated let stateHub = Broadcast<XxdConnectionState>(replay: true)
    private nonisolated let packetHub = Broadcast<XxdResponse>()
    /// Insertion-ordered: replies without a rid go to the oldest pending request of the same method.
    private var pending: [Pending] = []

    private var state: XxdConnectionState = .disconnected
    private var socket: XxdSocket?
    private var frameTask: Task<Void, Never>?
    private var codec: XxdFrameCodec?
    private var session: XxdSession?
    private var sessionId: String?
    private var generation = 0
    private var attempt = 0
    private var stopRequested = false
    private var lastFrameAt = Date()
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    public init(credentials: XxdCredentials, http: any XxdHttpClient = XxdHttpDatasource(),
                connector: @escaping XxdSocketConnector = urlSessionXxdConnector,
                pingInterval: TimeInterval = 60, requestTimeout: TimeInterval = 15,
                backoff: @escaping @Sendable (Int) -> TimeInterval = defaultXxdBackoff) {
        self.credentials = credentials; self.http = http; self.connector = connector
        self.pingInterval = pingInterval; self.requestTimeout = requestTimeout; self.backoff = backoff
        self.log = XxdTrafficLog()
    }

    public var currentState: XxdConnectionState { state }
    public nonisolated var states: AsyncStream<XxdConnectionState> { stateHub.stream() }
    /// Every decoded packet.
    public nonisolated var packets: AsyncStream<XxdResponse> { packetHub.stream() }

    /// Logs in. Network-type failures keep retrying in the background (`.reconnecting`); auth and certificate failures stop (`.stopped`).
    public func start() async -> Outcome<XxdSession> {
        if case .online(let s) = state { return .success(s) }
        stopRequested = false
        attempt = 0
        reconnectTask?.cancel()
        return await connect()
    }

    /// Sends `request` and waits for its reply (matched by `rid`, 15 s timeout).
    public func request(_ request: XxdRequest) async -> Outcome<XxdResponse> {
        guard case .online = state, let session else { return .failure(.network("Chat is offline")) }
        let rid = request.rid ?? UUID().uuidString
        let slot = expect(rid: rid, apiName: request.apiName)
        let started = Date()
        if case .failure(let f) = await send(addressed(request, session, rid: rid)) {
            pending.removeAll { $0.rid == rid }
            log.failed(request.apiName, Date().timeIntervalSince(started), f)
            return .failure(f)
        }
        let result = await slot.wait()
        switch result {
        case .success(let p): log.reply(request.apiName, Date().timeIntervalSince(started), p)
        case .failure(let f): log.failed(request.apiName, Date().timeIntervalSince(started), f)
        }
        if case .success(let p) = result, !p.isSuccess { return .failure(.unexpected(p.message ?? "\(p.apiName) failed")) }
        return result
    }

    /// Sends `request` without waiting for a reply, for messages the server does not answer (`chattyping`).
    public func notify(_ request: XxdRequest) async -> Outcome<Void> {
        guard case .online = state, let session else { return .failure(.network("Chat is offline")) }
        return await send(addressed(request, session, rid: request.rid))
    }

    private func addressed(_ r: XxdRequest, _ s: XxdSession, rid: String?) -> XxdRequest {
        XxdRequest(r.method, params: r.params, fields: r.fields, rid: rid, userId: r.userId ?? s.userId, module: r.module)
    }

    /// Ends the session without reconnecting.
    public func stop() async {
        stopRequested = true
        reconnectTask?.cancel()
        await teardown(.network("Chat connection closed"))
        setState(.disconnected)
    }

    public func dispose() async {
        await stop()
        stateHub.finish()
        packetHub.finish()
    }

    // MARK: connect

    private func connect() async -> Outcome<XxdSession> {
        generation += 1
        let gen = generation
        setState(.connecting)
        let result = await login(gen)
        if gen != generation || stopRequested { return result }
        switch result {
        case .success(let s):
            attempt = 0
            session = s
            setState(.online(s))
            startKeepAlive(gen)
        case .failure(let f):
            await teardown(f)
            retryOrStop(f)
        }
        return result
    }

    private func login(_ gen: Int) async -> Outcome<XxdSession> {
        let info: XxdServerInfo
        switch await http.fetchServerInfo(credentials) {
        case .success(let i): info = i
        case .failure(let f): return .failure(f)
        }
        do {
            let scheme = info.apiScheme.map { ApiSchemeCodec($0) }
            codec = XxdFrameCodec(clientVersion: http.clientVersion, lang: http.lang, device: http.device,
                                  serverName: credentials.serverName, scheme: scheme,
                                  cipher: info.enableClientAes ? try XxdCipher(token: info.token) : nil)
        } catch { return .failure(.parse("Unusable chat session token")) }

        guard let url = info.socketURL(server: credentials.server) else { return .failure(.network("Bad chat socket address")) }
        let opened = await open(url)
        switch opened {
        case .success(let s): attach(s, gen)
        case .failure(let f): return .failure(f)
        }

        let rid = "login_\(http.device)_\(credentials.account)"
        let slot = expect(rid: rid, apiName: "userlogin")
        let started = Date()
        let params: [JSONValue] = [.string(credentials.serverName), .string(credentials.account),
                                   .string(XxdSigning.passwordAuthKey(credentials.password)),
                                   ["status": "online", "simple": false]]
        if case .failure(let f) = await send(XxdRequest("userLogin", params: params, rid: rid)) { return .failure(f) }
        let reply = await slot.wait()
        switch reply {
        case .success(let p): log.reply("userlogin", Date().timeIntervalSince(started), p)
        case .failure(let f): log.failed("userlogin", Date().timeIntervalSince(started), f)
        }
        switch reply {
        case .failure(let f): return .failure(f)
        case .success(let p):
            guard p.isSuccess, case .object(let user)? = p.data else {
                return .failure(.auth(p.message ?? "Chat login rejected"))
            }
            return .success(XxdSession(user: user, serverVersion: info.version, sessionId: sessionId,
                                       token: info.token, uploadFileSize: info.uploadFileSize))
        }
    }

    private func open(_ url: URL) async -> Outcome<XxdSocket> {
        let policy = XxdTLSPolicy(pinnedFingerprint: credentials.pinnedFingerprint)
        do { return .success(try await connector(url, policy)) }
        catch { return .failure(xxdMapTransportError(error, policy: policy, fallback: "Cannot open the chat socket")) }
    }

    private func attach(_ socket: XxdSocket, _ gen: Int) {
        self.socket = socket
        lastFrameAt = Date()
        frameTask = Task { [weak self] in
            do {
                for try await frame in socket.frames { await self?.onFrame(frame, gen) }
                // A teardown cancels this task first: our own close is not a drop.
                if Task.isCancelled { return }
                await self?.onEnded(gen, .network("Chat socket closed (\(socket.closeCode.map(String.init) ?? "-") \(socket.closeReason ?? ""))"))
            } catch {
                if Task.isCancelled { return }
                await self?.onEnded(gen, .network("Chat socket error: \(error.localizedDescription)"))
            }
        }
    }

    private func onEnded(_ gen: Int, _ f: Failure) async { if gen == generation { await onDropped(f) } }

    // MARK: traffic

    private func send(_ request: XxdRequest) async -> Outcome<Void> {
        guard let socket, let codec else { return .failure(.network("Chat socket is not open")) }
        do {
            try await socket.send(try codec.encode(request))
            log.request(request)
            return .success(())
        } catch let e as XxdProtocolError { return .failure(.parse(e.message)) }
        catch { return .failure(.network("Cannot send on the chat socket: \(error.localizedDescription)")) }
    }

    private func expect(rid: String, apiName: String) -> XxdReplySlot {
        let slot = XxdReplySlot()
        pending.append(Pending(rid: rid, apiName: apiName, slot: slot))
        let timeout = requestTimeout
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1e9))
            await self?.expire(rid, slot, apiName)
        }
        return slot
    }

    private func expire(_ rid: String, _ slot: XxdReplySlot, _ apiName: String) {
        guard !slot.isCompleted else { return }
        pending.removeAll { $0.slot === slot }
        slot.complete(.failure(.network("No reply to \(apiName) from chat server")))
    }

    private func onFrame(_ frame: XxdFrame, _ gen: Int) {
        guard gen == generation else { return }
        lastFrameAt = Date()
        guard let codec else { return }
        let packets: [XxdResponse]
        do { packets = try codec.decode(frame) } catch { return }
        for p in packets {
            route(p)
            packetHub.send(p)
        }
    }

    private func route(_ packet: XxdResponse) {
        switch packet.apiName {
        case "syssessionid":
            let id: String? = {
                if let s = packet.data?.string, !s.isEmpty { return s }
                return packet.raw["sessionID"]?.string
            }()
            if let id {
                sessionId = id
                if let s = session?.withSessionId(id), case .online = state { session = s; setState(.online(s)) }
            }
        case "userkickoff":
            Task { await self.kicked(packet) }
            return
        default: break
        }
        let taken: Pending?
        if let rid = packet.rid, !rid.isEmpty {
            taken = pending.firstIndex { $0.rid == rid }.map { pending.remove(at: $0) }
        } else {
            taken = pending.firstIndex { $0.apiName == packet.apiName }.map { pending.remove(at: $0) }
        }
        if let taken { taken.slot.complete(.success(packet)) } else { log.push(packet) }
    }

    private func kicked(_ packet: XxdResponse) async {
        stopRequested = true
        reconnectTask?.cancel()
        let reason = packet.raw["reason"].map { JS.toString($0) } ?? packet.message
        let f = Failure.auth("Signed out: the account logged in elsewhere" + (reason.map { " (\($0))" } ?? ""))
        await teardown(f)
        setState(.stopped(f, kicked: true))
    }

    // MARK: keep-alive & reconnect

    private func startKeepAlive(_ gen: Int) {
        pingTask?.cancel()
        let interval = pingInterval
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1e9))
                if Task.isCancelled { return }
                await self?.pingTick(gen)
            }
        }
    }

    private func pingTick(_ gen: Int) async {
        guard gen == generation else { return }
        if Date().timeIntervalSince(lastFrameAt) > pingInterval * 2 {
            await onDropped(.network("Chat server stopped responding"))
            return
        }
        _ = await send(XxdRequest("ping", userId: session?.userId))
    }

    private func onDropped(_ f: Failure) async {
        if stopRequested { return }
        generation += 1 // ignore late events from this socket
        let gen = generation
        await teardown(f)
        if gen == generation && !stopRequested { retryOrStop(f) }
    }

    private func retryOrStop(_ f: Failure) {
        if stopRequested { return }
        switch f {
        case .auth, .untrustedCertificate: setState(.stopped(f, kicked: false)); return
        default: break
        }
        attempt += 1
        let delay = backoff(attempt)
        setState(.reconnecting(attempt: attempt, delay: delay, lastFailure: f))
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
            if Task.isCancelled { return }
            await self?.reconnectFired()
        }
    }

    private func reconnectFired() async { if !stopRequested { _ = await connect() } }

    private func teardown(_ f: Failure) async {
        pingTask?.cancel(); pingTask = nil
        session = nil; sessionId = nil
        let waiting = pending
        pending.removeAll()
        for p in waiting { p.slot.complete(.failure(f)) }
        // Detach before closing so our own close is not mistaken for a drop.
        frameTask?.cancel(); frameTask = nil
        let s = socket
        socket = nil
        await s?.close(code: 1000, reason: "bye")
    }

    private func setState(_ s: XxdConnectionState) {
        if !(state.isOnline && s.isOnline) { log.state(s) }
        state = s
        stateHub.send(s)
    }
}
