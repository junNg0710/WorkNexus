import CoreDomain
import Foundation

/// Typing signals: incoming `chattyping` pushes become `ChatTypingSignal`s; outgoing ones go to the peer or the group's members.
/// Ported from: lib/features/chat/data/repositories/chat_typing_channel.dart
final class ChatTypingChannel: @unchecked Sendable {
    typealias MembersLoader = @Sendable (String, String) async -> Outcome<[Int]>
    private let members: MembersLoader
    private let hubs = Locked<[String: Broadcast<ChatTypingSignal>]>([:])
    private let groupMembers = Locked<[String: [String: [Int]]]>([:])

    init(members: @escaping MembersLoader) { self.members = members }

    func watch(_ accountId: String) -> AsyncStream<ChatTypingSignal> { hub(accountId).stream() }

    /// Consumes a `chattyping` packet (true when it was one).
    func handle(_ accountId: String, _ packet: XxdResponse) -> Bool {
        guard packet.apiName == "chattyping" else { return false }
        guard packet.isSuccess, case .object(let data)? = packet.data else { return true }
        let typing: Bool? = {
            switch data["typing"] {
            case .bool(let b)?: return b
            case .int(let n)?: return n != 0
            case .double(let n)?: return n != 0
            // xxd relays the flag as a string ("true" / "false").
            case .string(let s)?: switch s.lowercased() { case "true", "1": return true; case "false", "0": return false; default: return nil }
            default: return nil
            }
        }()
        if let gid = data["cgid"]?.string, let user = ChatMappers.int(data["user"]), let typing {
            hub(accountId).send(ChatTypingSignal(chatGid: gid, userId: user, typing: typing))
        }
        return true
    }

    func send(_ session: ChatSession?, _ accountId: String, _ chatGid: String, typing: Bool) async -> Outcome<Void> {
        // The connection knows who signed in before `selfUserId` is copied over from its state change.
        guard let session, let me = await session.onlineSession()?.userId else { return .success(()) }
        let users: [Int]
        if let peer = ChatMappers.peer(of: chatGid, selfUserId: me) { users = [peer] }
        else {
            switch await groupMembersOf(accountId, chatGid) {
            case .success(let ids): users = ids.filter { $0 != me }
            case .failure(let f): return .failure(f)
            }
        }
        if users.isEmpty { return .success(()) }
        return await session.connection.notify(XxdRequest("chattyping", fields: [("cgid", .string(chatGid)), ("users", .array(users.map { .int($0) })), ("typing", .bool(typing))]))
    }

    func forget(_ accountId: String) { groupMembers.with { $0[accountId] = nil } }

    private func groupMembersOf(_ accountId: String, _ chatGid: String) async -> Outcome<[Int]> {
        if let cached = groupMembers.current[accountId]?[chatGid] { return .success(cached) }
        let loaded = await members(accountId, chatGid)
        if case .success(let ids) = loaded { groupMembers.with { $0[accountId, default: [:]][chatGid] = ids } }
        return loaded
    }

    private func hub(_ accountId: String) -> Broadcast<ChatTypingSignal> {
        hubs.with { h in
            if let b = h[accountId] { return b }
            let b = Broadcast<ChatTypingSignal>(); h[accountId] = b; return b
        }
    }
}
