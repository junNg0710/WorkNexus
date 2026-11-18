/// Ported from: lib/features/chat/presentation/providers/sticker_suggestion_providers.dart +
/// lib/features/chat/presentation/widgets/chat_sticker_suggestions_bar.dart (`_ChatStickerSuggestionsBarState`)
import CoreDomain
import Foundation
import Observation

/// The stickers offered over a composer: while typing, stickers for the words or emoji typed; with nothing typed, stickers
/// answering the chat's newest message when it is someone else's. All of it lives in the composer, so typing never touches
/// the message rows.
@MainActor @Observable
final class ChatStickerSuggester {
    /// What the strip shows, and whether a sticker picked from it stands for the whole draft (it is then cleared).
    struct Offer: Equatable {
        var stickers: [ChatSticker]
        /// Stickers for what is typed (true) or to answer the newest message (false).
        var typing: Bool
        var replacesDraft: Bool
    }

    /// How long typing settles before the stickers follow it.
    static let settle: Duration = .milliseconds(200)

    /// The draft as the suggestions last saw it (follows typing after `settle`).
    private(set) var draft = ""
    /// Every sticker that can be suggested: the ones tagged with an emoji.
    private(set) var tagged: [ChatSticker] = []
    private(set) var latest: ChatMessage?
    /// The draft the strip was closed for; it comes back once that changes.
    private var closedFor: String?
    /// The message whose sticker replies were closed, so they stay closed until another message comes.
    private var dismissedReplyFor: String?
    @ObservationIgnored private var settling: Task<Void, Never>?
    @ObservationIgnored private var loaded = false

    /// `inThread`: replies are offered only under the chat itself, not in a reply thread.
    let inThread: Bool
    init(inThread: Bool) { self.inThread = inThread }

    /// What to offer now; nil when nothing (or suggestions are off).
    func offer(enabled: Bool) -> Offer? {
        guard enabled, !tagged.isEmpty else { return nil }
        if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard closedFor != draft else { return nil }
            let found = SuggestStickers()(draft, tagged)
            return found.stickers.isEmpty ? nil : Offer(stickers: found.stickers, typing: true, replacesDraft: found.replacesDraft)
        }
        guard !inThread, let latest, dismissedReplyFor != latest.gid else { return nil }
        let replies = SuggestReplyStickers()(latest, tagged)
        return replies.isEmpty ? nil : Offer(stickers: replies, typing: false, replacesDraft: false)
    }

    /// The input changed: the suggestions follow once typing settles.
    func typed(_ text: String) {
        settling?.cancel()
        settling = Task { [weak self] in
            try? await Task.sleep(for: Self.settle)
            guard !Task.isCancelled else { return }
            self?.draft = text
        }
    }

    /// The input was cleared at once (a send): no settling, the old draft must not linger.
    func cleared() { settling?.cancel(); draft = "" }

    /// ✕ on the strip: hides it for this draft, or for this newest message.
    func close() {
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { dismissedReplyFor = latest?.gid } else { closedFor = draft }
    }

    /// Loads the tagged stickers once per composer.
    func load(_ repository: StickerRepository?) async {
        guard !loaded, let repository else { return }
        loaded = true
        if case .success(let all) = await repository.stickers() { tagged = all.filter { !$0.emoji.isEmpty } }
    }

    /// Follows the chat's newest message (whatever window its list shows) while the composer is up.
    func watchLatest(_ repository: ChatRepository, accountId: String, chatGid: String) async {
        guard !inThread else { return }
        for await messages in repository.watchMessages(accountId: accountId, chatGid: chatGid, limit: 1, reactions: false) {
            let newest = messages.last
            if newest?.gid != latest?.gid || newest?.deleted != latest?.deleted { latest = newest }
        }
    }

    func stop() { settling?.cancel() }
}
