import CoreDomain
import Foundation

/// History paging against xxd's `messageSync`/`messageGetList`, storing pages through the ingestor (serialized by the session queue).
/// Ported from: lib/features/chat/data/repositories/chat_history_sync.dart
final class ChatHistorySync: @unchecked Sendable {
    static let pageSize = 50
    private let local: ChatLocalDatasource
    private let ingestor: ChatPacketIngestor

    init(local: ChatLocalDatasource, ingestor: ChatPacketIngestor) { self.local = local; self.ingestor = ingestor }

    private static let offline: Outcome<Int> = .failure(.network("Chat is offline"))

    /// Brings the newest page of a chat into the timeline and cuts off older stored rows it does not reach.
    func refresh(_ session: ChatSession?, _ accountId: String, _ chatGid: String) async -> Outcome<Void> {
        guard let session else { return .failure(.network("Chat is offline")) }
        let last: Int
        switch await session.connection.request(XxdRequest("chatGetMessageInfo", params: [.string(chatGid)])) {
        case .success(let r): last = ChatMappers.int(r.data?["lastMessage"]) ?? 0
        case .failure(let f): return .failure(f)
        }
        if last <= 0 { return .success(()) }
        switch await syncPage(session, accountId, chatGid, from: last, link: .linked) {
        case .failure(let f): return .failure(f)
        case .success(let page):
            if let oldest = Self.indexes(page).min() {
                let local = local
                await session.enqueue { try? await local.timeline.detachIfCutOffBelow(accountId, chatGid, oldest) }
            }
            return .success(())
        }
    }

    func messageCount(_ session: ChatSession?, _ chatGid: String) async -> Outcome<Int> {
        guard let session else { return Self.offline }
        switch await session.connection.request(XxdRequest("chatGetMessageInfo", params: [.string(chatGid)])) {
        case .success(let r): return .success(ChatMappers.int(r.data?["messageCount"]) ?? 0)
        case .failure(let f): return .failure(f)
        }
    }

    func loadOlder(_ session: ChatSession?, _ accountId: String, _ chatGid: String, before: Int?, inWindow: Bool, pageSize: Int?) async -> Outcome<Int> {
        guard let session else { return Self.offline }
        let oldestStored = try? await local.oldestServerId(accountId, chatGid)
        guard let oldest = before ?? oldestStored else {
            switch await refresh(session, accountId, chatGid) { case .success: return .success(0); case .failure(let f): return .failure(f) }
        }
        if oldest <= 1 { return .success(0) }
        switch await syncPage(session, accountId, chatGid, from: oldest - 1, link: inWindow ? .detached : .linked, limit: pageSize) {
        case .success(let page): return .success(page.filter { (ChatMappers.int($0["id"]) ?? oldest) < oldest }.count)
        case .failure(let f): return .failure(f)
        }
    }

    func fetchByIds(_ session: ChatSession?, _ accountId: String, _ chatGid: String, _ ids: [Int]) async -> Outcome<Void> {
        if ids.isEmpty { return .success(()) }
        guard let session else { return .failure(.network("Chat is offline")) }
        switch await session.connection.request(XxdRequest("messageGetList", params: [.string(chatGid), .array(ids.map { .int($0) })])) {
        case .success(let r): _ = await store(session, accountId, r.data, .detached); return .success(())
        case .failure(let f): return .failure(f)
        }
    }

    /// A window around `serverId`: a page each way (`messageSync` pages by server message id), stored detached.
    func loadAround(_ session: ChatSession?, _ accountId: String, _ chatGid: String, _ serverId: Int) async -> Outcome<(from: Int, to: Int)?> {
        guard let session else { return .failure(.network("Chat is offline")) }
        let older = await syncPage(session, accountId, chatGid, from: serverId, link: .detached)
        if case .failure(let f) = older { return .failure(f) }
        let newer = await syncPage(session, accountId, chatGid, from: serverId, link: .detached, reverse: false)
        var indexes = Self.indexes(older.value ?? [])
        // Newer is a bonus: without it the window still holds the target.
        indexes += Self.indexes(newer.value ?? [])
        guard let lo = indexes.min(), let hi = indexes.max() else { return .success(nil) }
        return .success((lo, hi))
    }

    func loadNewer(_ session: ChatSession?, _ accountId: String, _ chatGid: String, after: Int) async -> Outcome<Int> {
        guard let session else { return Self.offline }
        switch await syncPage(session, accountId, chatGid, from: after + 1, link: .detached, reverse: false) {
        case .success(let page): return .success(page.filter { (ChatMappers.int($0["id"]) ?? 0) > after }.count)
        case .failure(let f): return .failure(f)
        }
    }

    private func syncPage(_ session: ChatSession, _ accountId: String, _ chatGid: String, from: Int, link: MessageLink,
                          reverse: Bool = true, limit: Int? = nil) async -> Outcome<[JSONObject]> {
        let params: [JSONValue] = [.string(chatGid), .int(from), .bool(reverse), .int(limit ?? Self.pageSize), .bool(false)]
        switch await session.connection.request(XxdRequest("messageSync", params: params)) {
        case .success(let r): return .success(await store(session, accountId, r.data, link))
        case .failure(let f): return .failure(f)
        }
    }

    private static func indexes(_ messages: [JSONObject]) -> [Int] { messages.compactMap { ChatMappers.int($0["index"]) } }

    private func store(_ session: ChatSession, _ accountId: String, _ data: JSONValue?, _ link: MessageLink) async -> [JSONObject] {
        let messages = ChatPacketIngestor.objects(data)
        let ingestor = ingestor
        await session.enqueue {
            if let followUp = try? await ingestor.storeMessages(accountId, messages, selfUserId: session.selfUserId, link: link) {
                session.fetchMissing(followUp)
            }
        }
        return messages
    }
}
