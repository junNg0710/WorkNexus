import CoreDomain
import Foundation

/// One account's live chat: the xxd connection, the serialized write queue (packets are stored strictly in arrival order)
/// and the signed-in user's id.
/// Ported from: lib/features/chat/data/repositories/chat_session.dart
final class ChatSession: @unchecked Sendable {
    let connection: XxdConnection
    private let queue = SerialQueue()
    private let selfId = Locked<Int?>(nil)
    private var tasks: [Task<Void, Never>] = []

    init(connection: XxdConnection) { self.connection = connection }

    var selfUserId: Int? {
        get { selfId.current }
        set { selfId.with { $0 = newValue } }
    }

    func isOnline() async -> Bool { await connection.currentState.isOnline }

    /// Active = running or retrying; stopped (auth, certificate, kicked) and disconnected sessions are not.
    func isActive() async -> Bool {
        switch await connection.currentState { case .stopped, .disconnected: false; default: true }
    }

    func onlineSession() async -> XxdSession? { await connection.currentState.session }

    /// Starts feeding packets and state changes to the handlers. Subscribe before `connection.start()`.
    func listen(onPacket: @escaping @Sendable (XxdResponse) -> Void, onState: @escaping @Sendable (XxdConnectionState) -> Void) {
        let packets = connection.packets, states = connection.states
        tasks.append(Task { for await p in packets { onPacket(p) } })
        tasks.append(Task { for await s in states { onState(s) } })
    }

    /// Runs `work` after every earlier queued job (errors are the job's to handle).
    func enqueue(_ work: @escaping @Sendable () async -> Void) async { await queue.run(work) }

    /// Queues `work` synchronously (call order is run order); use from a packet handler so packets are stored in arrival order.
    func submit(_ work: @escaping @Sendable () async -> Void) { queue.submit(work) }

    func fetchMissing(_ followUp: IngestFollowUp) {
        let c = connection
        if !followUp.userIds.isEmpty {
            let ids = followUp.userIds.sorted().map { JSONValue.int($0) }
            Task { _ = await c.request(XxdRequest("usergetlist", params: [.array(ids)])) }
        }
        for gid in followUp.chatGids { Task { _ = await c.request(XxdRequest("chatgetbygid", params: [.string(gid)])) } }
    }

    func close() async {
        tasks.forEach { $0.cancel() }
        tasks = []
        await connection.dispose()
    }
}

/// The connection status of one account, replayed to new watchers.
final class StatusChannel: @unchecked Sendable {
    private let hub = Broadcast<ChatConnectionStatus>(replay: true)
    private let value = Locked<ChatConnectionStatus>(.offline)
    init() { hub.send(.offline) }

    func set(_ status: ChatConnectionStatus) {
        let changed = value.with { v -> Bool in if v == status { return false }; v = status; return true }
        if changed { hub.send(status) }
    }

    func watch() -> AsyncStream<ChatConnectionStatus> { hub.stream() }
}
