import CoreDomain
import CorePersistence
import Foundation

/// The chat repository over xxd: one `ChatSession` per account, the database as the source of truth.
/// This file holds connection handling and ingest; reads, history and sending live in the `XxdChatRepository+…` extensions.
/// Ported from: lib/features/chat/data/repositories/xxd_chat_repository.dart
public final class XxdChatRepository: ChatRepository, @unchecked Sendable {
    typealias ConnectionFactory = @Sendable (XxdCredentials) -> XxdConnection

    static let pendingTimeout: TimeInterval = 120

    let local: ChatLocalDatasource
    let ingestor: ChatPacketIngestor
    let resolver: ChatCredentialsResolver
    let history: ChatHistorySync
    let files: ChatFileCache
    let attachments: ChatAttachmentLoader
    let cacheManager: ChatCacheManager
    let avatars: ChatAvatarService
    let savedCopies: ChatSavedCopies
    let http: any XxdHttpClient
    let openConnection: ConnectionFactory
    let now: @Sendable () -> Date
    let sessions = Locked<[String: ChatSession]>([:])
    let statuses = Locked<[String: StatusChannel]>([:])
    let connecting = Locked<[String: Task<Outcome<Void>, Never>]>([:])
    let presences = Locked<[String: ChatPresence]>([:])
    let roleNameCache = Locked<[String: [String: String]]>([:])
    let incoming = Broadcast<ChatMessage>()
    let videoAutoDownloadBytes = Locked(20 * 1024 * 1024)
    private(set) var sender: ChatSender!
    private(set) var typing: ChatTypingChannel!

    init(db: AppDatabase, credentials: CredentialStore, http: any XxdHttpClient = XxdHttpDatasource(), files: ChatFileCache? = nil,
         connection: ConnectionFactory? = nil, now: @escaping @Sendable () -> Date = Date.init) {
        local = ChatLocalDatasource(db: db)
        ingestor = ChatPacketIngestor(local: local)
        resolver = ChatCredentialsResolver(local: local, store: credentials)
        history = ChatHistorySync(local: local, ingestor: ingestor)
        self.files = files ?? ChatFileCache.appDefault()
        attachments = ChatAttachmentLoader(http: http, files: self.files)
        cacheManager = ChatCacheManager(local: local, files: self.files, attachments: attachments)
        avatars = ChatAvatarService(http: http)
        savedCopies = ChatSavedCopies(local: local, attachments: attachments, now: now)
        self.http = http; self.now = now
        openConnection = connection ?? { XxdConnection(credentials: $0, http: http) }
        sender = ChatSender(local: local, attachments: attachments, session: { [unowned self] in self.sessions.current[$0] },
                            ingest: { [unowned self] in await self.ingest($0, $1, $2) }, now: now)
        typing = ChatTypingChannel(members: { [unowned self] in await self.members(accountId: $0, chatGid: $1) })
    }

    func session(_ accountId: String) -> ChatSession? { sessions.current[accountId] }

    func status(_ accountId: String) -> StatusChannel {
        statuses.with { s in
            if let c = s[accountId] { return c }
            let c = StatusChannel(); s[accountId] = c; return c
        }
    }

    // MARK: connection

    public func watchStatus(accountId: String) -> AsyncStream<ChatConnectionStatus> { status(accountId).watch() }

    public func connect(accountId: String) async -> Outcome<Void> {
        if let running = connecting.current[accountId] { return await running.value }
        let task = Task { await connectOnce(accountId) }
        connecting.with { $0[accountId] = task }
        let result = await task.value
        connecting.with { $0[accountId] = nil }
        return result
    }

    private func connectOnce(_ accountId: String) async -> Outcome<Void> {
        if let existing = session(accountId), await existing.isActive() { return .success(()) }
        await closeSession(accountId)
        let creds: XxdCredentials
        switch await resolver.resolve(accountId) {
        case .success(let c): creds = c
        case .failure(let f):
            status(accountId).set(.signedOut(message: f.message))
            return .failure(f)
        }
        _ = try? await local.failStalePending(accountId, before: now().addingTimeInterval(-Self.pendingTimeout))

        let connection = openConnection(creds)
        let session = ChatSession(connection: connection)
        sessions.with { $0[accountId] = session }
        session.listen(
            onPacket: { [weak self, weak session] p in
                guard let self, let session else { return }
                // The login reply names the signed-in user before the packets that follow it need to know.
                if p.apiName == "userlogin", p.isSuccess, p.rid?.hasPrefix("login_") == true, let id = ChatMappers.int(p.data?["id"]) { session.selfUserId = id }
                if self.typing.handle(accountId, p) { return }
                session.submit { await self.ingest(accountId, session, p) }
            },
            onState: { [weak self, weak session] s in
                guard let self, let session else { return }
                self.onState(accountId, session, s)
            })
        switch await connection.start() {
        case .success: return .success(())
        case .failure(let f): return .failure(f)
        }
    }

    public func disconnect(accountId: String) async {
        await closeSession(accountId)
        status(accountId).set(.offline)
    }

    public func trustCertificate(accountId: String, fingerprint: String) async -> Outcome<Void> {
        do { try await local.saveChatAccount(accountId, pinnedFingerprint: .some(fingerprint)) }
        catch { return .failure(.storage("Could not save the certificate: \(error.localizedDescription)")) }
        await closeSession(accountId)
        return await connect(accountId: accountId)
    }

    private func onState(_ accountId: String, _ session: ChatSession, _ s: XxdConnectionState) {
        guard self.session(accountId) === session else { return }
        let status: ChatConnectionStatus
        switch s {
        case .disconnected: status = .offline
        case .connecting: status = .connecting
        case .online(let x): status = .online(selfUserId: x.userId)
        case .reconnecting(_, let delay, let failure): status = .reconnecting(retryIn: delay, reason: failure.message)
        case .stopped(.untrustedCertificate(_, let host, let fingerprint, let subject, let issuer), _):
            status = .needsTrust(host: host, fingerprint: fingerprint, subject: subject, issuer: issuer)
        case .stopped(let failure, let kicked): status = .signedOut(message: failure.message, kicked: kicked)
        }
        self.status(accountId).set(status)
        guard case .online(let x) = s else { return }
        session.selfUserId = x.userId
        // Notifications (and xuanbot) arrive as `syncNotifications` once asked for, as the official client does after signing in.
        let c = session.connection
        Task { _ = await c.request(XxdRequest("getNotification", params: [])) }
        let local = local
        session.submit { try? await local.saveChatAccount(accountId, userId: .some(x.userId)) }
        if let presence = presences.current[accountId], presence != .online {
            let req = userChange(session, presence)
            Task { _ = await c.request(req) }
        }
    }

    func closeSession(_ accountId: String) async {
        typing.forget(accountId)
        let s = sessions.with { $0.removeValue(forKey: accountId) }
        await s?.close()
    }

    func userChange(_ session: ChatSession, _ presence: ChatPresence) -> XxdRequest {
        XxdRequest("userupdate", params: [["account": .string(session.connection.credentials.account), "status": .string(presence.status)]])
    }

    // MARK: ingest

    public func watchIncoming() -> AsyncStream<ChatMessage> { incoming.stream() }

    func ingest(_ accountId: String, _ session: ChatSession, _ packet: XxdResponse) async {
        let me = session.selfUserId
        // Only a live push of a message not stored before is "new": the reply to our own send, re-deliveries and
        // retract/edit pushes are not.
        var fresh: [String] = []
        if packet.isSuccess, packet.apiName == "messagesend" {
            let items: [JSONValue] = packet.data?.array ?? (packet.data.map { [$0] } ?? [])
            for m in items {
                guard case .object(let o) = m, let gid = o["gid"]?.string, o["deleted"] != .bool(true) else { continue }
                if (try? await local.message(accountId, gid)) == nil { fresh.append(gid) }
            }
        }
        do {
            let followUp = try await ingestor.ingest(accountId, packet, selfUserId: me)
            session.fetchMissing(followUp)
        } catch { /* a failed write is dropped; the next page or reconnect re-stores it */ }
        for gid in fresh {
            guard let row = try? await local.message(accountId, gid), row.senderId != me else { continue }
            incoming.send(ChatMappers.message(row, selfUserId: me))
        }
    }

    /// Sends `request`, stores the reply (so the change shows at once) and maps a refusal to a failure.
    func requestAndStore(_ accountId: String, _ session: ChatSession, _ request: XxdRequest) async -> Outcome<Void> {
        switch await session.connection.request(request) {
        case .failure(let f): return .failure(f)
        case .success(let reply):
            if !reply.isSuccess { return .failure(.unexpected(reply.message ?? "The server refused")) }
            await session.enqueue { [self] in await ingest(accountId, session, reply) }
            return .success(())
        }
    }
}
