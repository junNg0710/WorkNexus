import CoreDomain
import Foundation

/// What the user asks of the chat server from the list and the dialogs (use cases and CRUD pass-through).
extension ChatShellModel {
    func connect() { Task { if case .failure(let f) = await ConnectChat(repository)(accountId) { report(f) } } }

    /// Trusts the pending certificate; returns the failure's text for the dialog to show.
    func trust(fingerprint: String) async -> String? {
        switch await TrustChatCertificate(repository)(accountId: accountId, fingerprint: fingerprint) {
        case .success: showTrust = false; return nil
        case .failure(let f): return ChatShellLabels.failureText(f)
        }
    }

    /// Opens (creating on first use) the one-to-one chat with `userId` and selects it.
    @discardableResult
    func openDirectChat(userId: Int) async -> Bool {
        switch await OpenDirectChat(repository)(accountId: accountId, userId: userId) {
        case .success(let gid): tab = .all; setSearch(""); select(gid); return true
        case .failure(let f): report(f); return false
        }
    }

    func createGroup(name: String, memberIds: [Int], isPublic: Bool = false) async -> Bool {
        switch await CreateGroupChat(repository)(accountId: accountId, name: name, memberIds: memberIds, isPublic: isPublic) {
        case .success(let gid): tab = .all; setSearch(""); select(gid); return true
        case .failure(let f): report(f); return false
        }
    }

    func setStarred(_ chat: ChatConversation, _ starred: Bool) {
        Task { if case .failure(let f) = await repository.setChatStarred(accountId: accountId, chatGid: chat.gid, starred: starred) { report(f) } }
    }

    func setMuted(_ chat: ChatConversation, _ muted: Bool) {
        Task { if case .failure(let f) = await repository.setChatMuted(accountId: accountId, chatGid: chat.gid, muted: muted) { report(f) } }
    }

    /// Forwards each message (in the order given) to each chat; reports the first failure. True when every chat got all.
    func forward(_ messages: [ChatMessage], to chatGids: [String]) async -> Bool {
        var first: Failure?
        for message in messages {
            if case .failure(let f) = await ForwardChatMessage(repository)(message, toChatGids: chatGids) { first = first ?? f }
        }
        if let first { report(first); return false }
        return true
    }

    func setPresence(_ p: ChatPresence) {
        Task { if case .failure(let f) = await repository.setMyPresence(accountId: accountId, presence: p) { report(f) } }
    }
}
