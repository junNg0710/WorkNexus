import CoreDomain
import Foundation

/// Creating and managing groups and filing chats under categories, with the official ZenTao client's xxd calls. Each reply
/// (also pushed to the other members) is stored by the ingestor, so the change shows at once.
/// Ported from: lib/features/chat/data/repositories/xxd_chat_repository.dart (createGroupChat … transferGroupOwnership)
extension XxdChatRepository {
    public func createGroupChat(accountId: String, name: String, memberIds: [Int], isPublic: Bool) async -> Outcome<String> {
        guard let session = session(accountId), let me = session.selfUserId else { return .failure(.network("Chat is offline")) }
        let gid = UUID().uuidString.lowercased()
        var seen = Set<Int>(), members: [JSONValue] = []
        for id in [me] + memberIds where seen.insert(id).inserted { members.append(.int(id)) }
        let params: [JSONValue] = [.string(gid), .string(name), "group", .array(members), 0, .bool(isPublic)]
        switch await requestAndStore(accountId, session, XxdRequest("chatCreate", params: params)) { case .success: return .success(gid); case .failure(let f): return .failure(f) }
    }

    public func renameGroupChat(accountId: String, chatGid: String, name: String) async -> Outcome<Void> {
        // The reply (`{gid, name}`) renames it locally.
        await groupRequest(accountId, "chatRename", [.string(chatGid), .string(name)])
    }

    public func dismissGroupChat(accountId: String, chatGid: String) async -> Outcome<Void> {
        // The reply carries `dismissDate`, which takes it off the chat list.
        await groupRequest(accountId, "chatDismiss", [.string(chatGid)])
    }

    public func addGroupMembers(accountId: String, chatGid: String, userIds: [Int]) async -> Outcome<Void> {
        // The reply is the group with its new members.
        await groupRequest(accountId, "chatInvite", [.string(chatGid), .array(userIds.map { .int($0) })])
    }

    public func removeGroupMembers(accountId: String, chatGid: String, userIds: [Int]) async -> Outcome<Void> {
        await groupRequest(accountId, "chatKick", [.string(chatGid), .array(userIds.map { .int($0) })])
    }

    public func leaveGroupChat(accountId: String, chatGid: String) async -> Outcome<Void> {
        // The reply is the group without this account, which takes it off the chat list (see the ingestor).
        await groupRequest(accountId, "chatLeave", [.string(chatGid)])
    }

    public func setChatCategory(accountId: String, chatGids: [String], category: String) async -> Outcome<Void> {
        // The reply (`{gids, category}`) refiles them locally.
        await groupRequest(accountId, "chatSetCategory", [.array(chatGids.map { .string($0) }), .string(category)])
    }

    public func setGroupSettings(accountId: String, chatGid: String, isPublic: Bool, adminInvite: Bool, committers: String) async -> Outcome<Void> {
        guard let session = session(accountId) else { return .failure(.network("Chat is offline")) }
        let config = JSONObject([("public", .bool(isPublic)), ("adminInvite", .bool(adminInvite)), ("committers", .string(committers))])
        let result = await requestAndStore(accountId, session, XxdRequest("chatSetConfig", params: [.string(chatGid), .object(config)]))
        if case .success = result { return result }
        // Servers older than `chatSetConfig` (the official client checks the version) take the two settings one by one and
        // have no `adminInvite`.
        if case .failure = await requestAndStore(accountId, session, XxdRequest("chatSetVisibility", params: [.string(chatGid), .bool(isPublic)])) {
            return result
        }
        return await requestAndStore(accountId, session, XxdRequest("chatSetCommitters", params: [.string(chatGid), .string(committers)]))
    }

    public func setGroupAdmins(accountId: String, chatGid: String, userIds: [Int], admin: Bool) async -> Outcome<Void> {
        guard let session = session(accountId), let me = session.selfUserId else { return .failure(.network("Chat is offline")) }
        return await requestAndStore(accountId, session, XxdRequest(admin ? "chatAddAdmins" : "chatRemoveAdmins",
                                                                    params: [.string(chatGid), .array(userIds.map { .int($0) }), .int(me)]))
    }

    public func transferGroupOwnership(accountId: String, chatGid: String, userId: Int) async -> Outcome<Void> {
        // The reply is the whole group with its new owner.
        await groupRequest(accountId, "chatChangeOwnership", [.string(chatGid), .int(userId)])
    }

    private func groupRequest(_ accountId: String, _ method: String, _ params: [JSONValue]) async -> Outcome<Void> {
        guard let session = session(accountId) else { return .failure(.network("Chat is offline")) }
        return await requestAndStore(accountId, session, XxdRequest(method, params: params))
    }
}
