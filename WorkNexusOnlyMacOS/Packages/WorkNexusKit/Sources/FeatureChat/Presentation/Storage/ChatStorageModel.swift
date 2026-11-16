/// Ported from: lib/features/chat/presentation/providers (chatCacheUsageProvider) + chat_storage_panel.dart (clear)
import CoreDomain
import Foundation
import Observation

/// How a chat of the storage list is named and drawn: its conversation and the account's users, as stored locally.
struct ChatStorageOwner {
    var chat: ChatConversation?
    var users: [Int: ChatUser]
}

/// The downloaded-files usage per chat, with the owner of each chat looked up locally for its title and avatar, and the
/// clear commands (all, one account's, one chat's). Reloads after every clear.
@MainActor @Observable
final class ChatStorageModel {
    private(set) var usage: ChatCacheUsage?
    private(set) var failed = false
    private(set) var owners: [String: ChatStorageOwner] = [:]
    @ObservationIgnored private let repository: ChatRepository

    init(repository: ChatRepository) { self.repository = repository }

    static func key(_ accountId: String, _ chatGid: String) -> String { "\(accountId)/\(chatGid)" }

    func load() async {
        switch await repository.cacheUsage() {
        case .success(let u):
            usage = u; failed = false
            await loadOwners(u)
        case .failure: if usage == nil { failed = true }
        }
    }

    private func loadOwners(_ u: ChatCacheUsage) async {
        for account in Set(u.chats.map(\.accountId)) {
            var chats = repository.watchConversations(accountId: account).makeAsyncIterator()
            var users = repository.watchUsers(accountId: account).makeAsyncIterator()
            let list = await chats.next() ?? [], people = Dictionary((await users.next() ?? []).map { ($0.userId, $0) }, uniquingKeysWith: { _, n in n })
            for c in u.chats where c.accountId == account {
                owners[Self.key(account, c.chatGid)] = ChatStorageOwner(chat: list.first { $0.gid == c.chatGid }, users: people)
            }
        }
    }

    func title(_ usage: ChatCacheChatUsage) -> String {
        let owner = owners[Self.key(usage.accountId, usage.chatGid)]
        return owner?.chat.map { ChatShellLabels.title($0, owner?.users ?? [:]) } ?? usage.chatGid
    }

    /// Deletes the downloaded files (all, or one chat's) and measures again. The failure's text when it did not work.
    func clear(accountId: String? = nil, chatGid: String? = nil) async -> String? {
        let result = await repository.clearCache(accountId: accountId, chatGid: chatGid)
        await load()
        if case .failure(let f) = result { return ChatShellLabels.failureText(f) }
        return nil
    }

    /// This chat's share of the cache (zeros when nothing of it is stored).
    func usage(accountId: String, chatGid: String) -> ChatCacheChatUsage {
        usage?.chats.first { $0.accountId == accountId && $0.chatGid == chatGid } ?? ChatCacheChatUsage(accountId: accountId, chatGid: chatGid, bytes: 0)
    }
}
