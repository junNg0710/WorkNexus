import Foundation

/// Shared by the sticker suggestions: folding, finding words in text and ranking stickers by the emoji they carry.
/// Ported from: lib/features/chat/domain/usecases/sticker_matching.dart
public enum StickerMatching {
    private static let fold = FoldSearchText()

    /// Emoji in text, each one whole (`👨‍💻` stays one, skin tones kept).
    private static let emojiPattern = RX(#"\p{Extended_Pictographic}(?:\x{FE0F}|[\x{1F3FB}-\x{1F3FF}])?(?:\x{200D}\p{Extended_Pictographic}\x{FE0F}?)*"#)

    /// Anything that is neither a letter nor a digit, made a space, so words can be found by the spaces around them.
    private static let punctuation = RX(#"[^\p{L}\p{N}]+"#)
    private static let space = RX(#"\s+"#)
    private static let ending = RX(#"[?!.…]+$"#)
    private static let symbolPatterns: [(RX, [String])] = StickerKeywords.symbols.map { (RX($0.0), emojiIn($0.1)) }

    /// `text` folded to the words in it, space separated, no punctuation.
    public static func words(_ text: String) -> String {
        punctuation.replace(fold(text)) { _ in " " }.trimmingCharacters(in: .whitespaces)
    }

    /// The emoji in `text`, in order.
    public static func emojiIn(_ text: String) -> [String] { emojiPattern.matches(text).map { bare($0.whole) } }

    /// The keys of `lexicon` that are whole words or phrases of `words`, the one nearest the end first (what was typed last
    /// matters most); keys found at the same place keep the lexicon's order.
    public static func keysIn(_ words: String, _ lexicon: [String]) -> [String] {
        let padded = " \(words) " as NSString
        var found: [(key: String, at: Int, order: Int)] = []
        for (order, key) in lexicon.enumerated() {
            let r = padded.range(of: " \(key) ", options: .backwards)
            if r.location != NSNotFound { found.append((key, r.location, order)) }
        }
        return found.sorted { $0.at != $1.at ? $0.at > $1.at : $0.order < $1.order }.map(\.key)
    }

    /// What the punctuation and emoticons in `text` stand for (`StickerKeywords.symbols`), the last typed first: tokens of
    /// their own (`?`, `=))`) and the run a message ends with (`không??`).
    public static func symbolsIn(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.isEmpty ? [""] : space.split(trimmed)
        let last = tokens.last ?? ""
        let end = ending.first(last)?.whole
        var found: [String] = []
        for token in (end.map { [$0] } ?? []) + tokens.reversed() {
            if let hit = symbolPatterns.first(where: { $0.0.hasMatch(token) }) { found += hit.1 }
        }
        return found
    }

    /// The emoji `lexicon` gives `text` when it is one of its entries as a whole (`1`, `0`: `StickerKeywords.number`); none
    /// otherwise.
    public static func wholeIn(_ text: String, _ lexicon: [String: String]) -> [String] {
        lexicon[text.trimmingCharacters(in: .whitespacesAndNewlines)].map(emojiIn) ?? []
    }

    /// The emoji of `sticker`, one by one.
    public static func stickerEmoji(_ sticker: ChatSticker) -> [String] { emojiIn(sticker.emoji) }

    /// Stickers that carry `targets` (most wanted first), best first: one whose own first emoji is wanted beats one that only
    /// carries it, and an earlier target beats a later one. `bonus` (by sticker id) adds to a sticker's score (keyword hits);
    /// stickers that score nothing are left out. Ties keep the set's order.
    public static func rank(_ stickers: [ChatSticker], _ targets: [String], max: Int = 8, bonus: [String: Int] = [:]) -> [ChatSticker] {
        var weight: [String: Int] = [:]
        for (i, emoji) in targets.enumerated() where weight[emoji] == nil { weight[emoji] = (targets.count - i) * 10 }
        var scored: [(sticker: ChatSticker, score: Int, order: Int)] = []
        for (order, sticker) in stickers.enumerated() {
            var score = bonus[sticker.id] ?? 0
            for (i, emoji) in stickerEmoji(sticker).enumerated() {
                if let w = weight[emoji] { score += i == 0 ? w * 2 : w }
            }
            if score > 0 { scored.append((sticker, score, order)) }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        return scored.prefix(max).map(\.sticker)
    }

    /// `emoji` without the presentation selector, so `❤️` and `❤` match.
    private static func bare(_ emoji: String) -> String {
        String(String.UnicodeScalarView(emoji.unicodeScalars.filter { $0 != "\u{FE0F}" }))
    }
}

/// Ported from: lib/features/chat/domain/usecases/sticker_matching.dart (`String.split(RegExp)`)
extension RX {
    /// The parts of `s` between the matches.
    func split(_ s: String) -> [String] {
        let ns = s as NSString
        var out: [String] = [], from = 0
        for m in matches(s) { out.append(ns.substring(with: NSRange(location: from, length: m.start - from))); from = m.end }
        out.append(ns.substring(from: from))
        return out
    }
}
