/// Ported from: lib/features/chat/presentation/providers/chat_typing_providers.dart (chatTypingUsersProvider)
import CoreDomain
import Foundation

extension MessageTimelineModel {
    /// Folds the chat's live typing signals into the roster; a peer's entry lapses by itself (`TypingRoster.ttl`).
    func observeTyping() async {
        for await signal in services.chat.watchTyping(accountId: accountId) {
            guard signal.chatGid == chatGid else { continue }
            typingRoster = typingRoster.apply(signal, now: Date(), selfUserId: state.selfUserId)
            publishTyping()
        }
    }

    /// Drops the entries that lapsed.
    func pruneTyping() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard typingRoster.nextExpiry != nil else { continue }
            let next = typingRoster.prune(Date())
            if next != typingRoster { typingRoster = next; publishTyping() }
        }
    }

    private func publishTyping() {
        let now = typingRoster.typing(in: chatGid)
        if now != typing { setTyping(now) }
    }
}
