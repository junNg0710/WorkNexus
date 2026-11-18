import Foundation

/// Stickers that could stand for what is being typed, and whether one would say all of it (`replacesDraft`: the draft is only
/// the matched words or emoji), in which case sending one clears the draft.
/// Ported from: lib/features/chat/domain/usecases/suggest_stickers.dart (`StickerSuggestions`)
public struct StickerSuggestions: Equatable, Sendable {
    public var stickers: [ChatSticker]
    public var replacesDraft: Bool
    public init(stickers: [ChatSticker], replacesDraft: Bool) { self.stickers = stickers; self.replacesDraft = replacesDraft }
    public static let none = StickerSuggestions(stickers: [], replacesDraft: false)
}

/// Suggests stickers for a draft, the way messengers do while you type: the emoji in it, the words it ends with
/// (`StickerKeywords.typed`), its punctuation or emoticons (`StickerKeywords.symbols`: `?`, `=))`) and a number typed alone
/// (`StickerKeywords.number`: `1` yes, `0` no) pick stickers carrying those emoji; a sticker's own words (`ship it`) pick it
/// first. Only short drafts get suggestions — a long message is not about to become a sticker.
/// Ported from: lib/features/chat/domain/usecases/suggest_stickers.dart
public struct SuggestStickers: Sendable {
    public var max: Int
    public var maxWords: Int
    public init(max: Int = 8, maxWords: Int = 6) { self.max = max; self.maxWords = maxWords }

    private static let typedKeys = StickerKeywords.typed.map(\.0)
    private static let typedEmoji = Dictionary(StickerKeywords.typed, uniquingKeysWith: { first, _ in first })

    public func callAsFunction(_ draft: String, _ stickers: [ChatSticker]) -> StickerSuggestions {
        let words = StickerMatching.words(draft)
        let typed = StickerMatching.emojiIn(draft)
        let symbols = StickerMatching.symbolsIn(draft)
        let number = StickerMatching.wholeIn(draft, StickerKeywords.number)
        let count = words.isEmpty ? 0 : words.split(separator: " ").count
        if (count == 0 && typed.isEmpty && symbols.isEmpty) || count > maxWords { return .none }

        let keys = StickerMatching.keysIn(words, Self.typedKeys)
        // Typed on its own (`?`, `=))`) a symbol is the point; ending a sentence it only colours it, after what the words say.
        var targets = number + typed
        if count == 0 { targets += symbols }
        for key in keys { targets += StickerMatching.emojiIn(Self.typedEmoji[key] ?? "") }
        if count > 0 { targets += symbols }
        // A sticker named for the very words typed beats any emoji match.
        var bonus: [String: Int] = [:]
        var hits = Set<String>()
        for sticker in stickers {
            let own = StickerMatching.keysIn(words, sticker.keywords)
            if let first = own.first {
                bonus[sticker.id] = 1000 + first.utf16.count
                hits.formUnion(own)
            }
        }
        let ranked = StickerMatching.rank(stickers, targets, max: max, bonus: bonus)
        if ranked.isEmpty { return .none }
        return StickerSuggestions(stickers: ranked,
                                  replacesDraft: words.isEmpty || !number.isEmpty || keys.contains(words) || hits.contains(words))
    }
}

/// Stickers to answer the latest message with, when it is someone else's and recent: what it says picks them
/// (`StickerKeywords.reply` — thanks is answered with a smile; `StickerKeywords.numberReply` — a lone `1` with a thumbs up),
/// and an emoji or emoticon in it (`=))`, `?`) is echoed. Nothing for the user's own message, a notice, or one older than
/// `maxAge`.
/// Ported from: lib/features/chat/domain/usecases/suggest_reply_stickers.dart
public struct SuggestReplyStickers: Sendable {
    public var max: Int
    public var maxAge: TimeInterval
    public init(max: Int = 6, maxAge: TimeInterval = 12 * 3600) { self.max = max; self.maxAge = maxAge }

    /// Mentions are sent as `[@Name](@#id)`; the name is not what it says.
    private static let mention = RX(#"\[@[^\]]+\]\(@#\d+\)"#)
    private static let replyKeys = StickerKeywords.reply.map(\.0)
    private static let replyEmoji = Dictionary(StickerKeywords.reply, uniquingKeysWith: { first, _ in first })

    public func callAsFunction(_ latest: ChatMessage?, _ stickers: [ChatSticker], now: Date = Date()) -> [ChatSticker] {
        guard let latest, !latest.isMine, !latest.deleted, !latest.isNotice, now.timeIntervalSince(latest.sentAt) <= maxAge else { return [] }
        let text: String
        switch latest.content {
        case .text(let t, _): text = Self.mention.replace(t) { _ in " " }
        case .emoji(let e): text = e
        default: return []
        }
        let words = StickerMatching.words(text)
        var targets = StickerMatching.wholeIn(text, StickerKeywords.numberReply)
        for key in StickerMatching.keysIn(words, Self.replyKeys) { targets += StickerMatching.emojiIn(Self.replyEmoji[key] ?? "") }
        targets += StickerMatching.emojiIn(text)
        targets += StickerMatching.symbolsIn(text)
        return StickerMatching.rank(stickers, targets, max: max)
    }
}
