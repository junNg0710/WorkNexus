/// Ported from: lib/features/chat/presentation/widgets/chat_mention_text_controller.dart (`_editBetween`, `_shift`)
import Foundation

/// A mention in the composer text: `@Name` at `start..<end` (UTF-16 offsets), meaning user `id`.
struct ChatTextMention: Hashable, Sendable {
    var start: Int
    var end: Int
    var id: Int
}

/// What an edit changed: `start..<oldEnd` of the old text was replaced by `inserted` characters.
struct ChatTextEdit: Equatable, Sendable {
    var start: Int
    var oldEnd: Int
    var inserted: Int
    var delta: Int { inserted - (oldEnd - start) }
}

enum ChatMentionEdit {
    private static let wireMention = try? NSRegularExpression(pattern: #"\[@([^\]]+)\]\(@#(\d+)\)"#)

    /// A sent message's text as it was typed: each `[@Name](@#id)` reads `@Name`, with where those mentions lie in it.
    static func typed(_ wire: String) -> (text: String, mentions: [ChatTextMention]) {
        let ns = wire as NSString
        var text = "", mentions: [ChatTextMention] = [], at = 0
        for match in wireMention?.matches(in: wire, range: NSRange(location: 0, length: ns.length)) ?? [] {
            text += ns.substring(with: NSRange(location: at, length: match.range.location - at))
            let label = "@" + ns.substring(with: match.range(at: 1))
            let start = (text as NSString).length
            text += label
            if let id = Int(ns.substring(with: match.range(at: 2))) {
                mentions.append(ChatTextMention(start: start, end: start + (label as NSString).length, id: id))
            }
            at = NSMaxRange(match.range)
        }
        text += ns.substring(from: at)
        return (text, mentions)
    }

    /// The changed range between `previous` and `next`: what they share at both ends is unchanged. A typed run ends at the
    /// caret, which settles where it began when the same letter repeats ("@An" -> "@Ann").
    static func between(_ previous: String, _ next: String, caret: Int?) -> ChatTextEdit {
        let a = Array(previous.utf16), b = Array(next.utf16)
        let shortest = min(a.count, b.count)
        var prefix = 0
        while prefix < shortest && a[prefix] == b[prefix] { prefix += 1 }
        let grown = b.count - a.count
        if grown > 0, let caret { prefix = max(0, min(prefix, caret - grown)) }
        var suffix = 0
        while suffix < shortest - prefix && a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        return ChatTextEdit(start: prefix, oldEnd: a.count - suffix, inserted: b.count - suffix - prefix)
    }

    /// `mentions` after `edit`: those before it stay, those after it move by the change in length, those it touches are gone.
    static func shift(_ mentions: [ChatTextMention], _ edit: ChatTextEdit) -> [ChatTextMention] {
        mentions.compactMap { m in
            if m.end <= edit.start { return m }
            if m.start >= edit.oldEnd { return ChatTextMention(start: m.start + edit.delta, end: m.end + edit.delta, id: m.id) }
            return nil
        }
    }

    /// The edit widened so a deletion that reaches into a mention removes it whole.
    static func widenedForMentions(_ edit: ChatTextEdit, _ mentions: [ChatTextMention]) -> ChatTextEdit {
        guard edit.inserted == 0 else { return edit }
        var out = edit
        for m in mentions where m.start < out.oldEnd && m.end > out.start {
            out.start = min(out.start, m.start)
            out.oldEnd = max(out.oldEnd, m.end)
        }
        return out
    }
}
