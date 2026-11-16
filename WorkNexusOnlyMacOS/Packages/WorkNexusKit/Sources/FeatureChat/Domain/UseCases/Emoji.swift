import Foundation

/// Shows what `EncodeEmoji` and the official client send as emoji again: Emojione `:shortname:`s and HTML numeric
/// entities (`&#x1F44D;`, `&#128077;`). Unknown shortnames are left as typed.
/// Ported from: lib/features/chat/domain/usecases/decode_emoji.dart
public struct DecodeEmoji: Sendable {
    public init() {}
    private static let token = RX(#":([a-z0-9_+\-]+):|&#x([0-9a-fA-F]{1,6});|&#([0-9]{1,7});"#)

    public func callAsFunction(_ text: String) -> String {
        guard text.contains(":") || text.contains("&#") else { return text }
        return Self.token.replace(text) { m in
            if let name = m[1] {
                return ChatEmojiTables.shortnames[name]
                    ?? ChatEmojiTables.aliases[name].flatMap { ChatEmojiTables.shortnames[$0] } ?? m.whole
            }
            let rune = m[2].flatMap { UInt32($0, radix: 16) } ?? m[3].flatMap { UInt32($0) }
            if let rune, rune > 0, rune <= 0x10FFFF, let u = Unicode.Scalar(rune) { return String(Character(u)) }
            return m.whole
        }
    }
}

/// Makes text safe for the xxd server, whose database keeps only 3-byte UTF-8: a 4-byte character such as 👍 is stored
/// as "????". Emoji the official client knows become its Emojione shortnames (`:thumbsup:`, `:flag_vn:` — whole
/// sequences); any other 4-byte character becomes an HTML numeric entity.
/// Ported from: lib/features/chat/domain/usecases/encode_emoji.dart
public struct EncodeEmoji: Sendable {
    public init() {}
    private static let variationSelector: UInt32 = 0xFE0F

    public func callAsFunction(_ text: String) -> String {
        let runes = text.unicodeScalars.map(\.value)
        guard runes.contains(where: { $0 > 0xFFFF }) else { return text }
        var out = ""
        var i = 0
        while i < runes.count {
            if let m = match(runes, i) { out += ":\(m.name):"; i += m.length; continue }
            let r = runes[i]; i += 1
            if r <= 0xFFFF { out.unicodeScalars.append(Unicode.Scalar(r) ?? "\u{FFFD}") }
            else { out += "&#x\(String(r, radix: 16, uppercase: true));" }
        }
        return out
    }

    /// The longest known emoji starting at `start` that needs encoding; variation selectors are ignored.
    private func match(_ runes: [UInt32], _ start: Int) -> (name: String, length: Int)? {
        if runes[start] == Self.variationSelector { return nil }
        let end = min(runes.count, start + ChatEmojiTables.longestSequence + 4)
        var stop = end
        while stop > start {
            defer { stop -= 1 }
            let part = runes[start..<stop]
            guard part.contains(where: { $0 > 0xFFFF }) else { continue }
            var key = String.UnicodeScalarView()
            for r in part where r != Self.variationSelector { if let u = Unicode.Scalar(r) { key.append(u) } }
            if let name = ChatEmojiTables.canonicalNames[String(key)] { return (name, stop - start) }
        }
        return nil
    }
}

/// Whether `text` is just one emoji the official client knows (surrounding whitespace and variation selectors aside) —
/// such a message is sent as a large emoji instead of a text bubble.
/// Ported from: lib/features/chat/domain/usecases/is_single_emoji.dart
public struct IsSingleEmoji: Sendable {
    public init() {}
    public func callAsFunction(_ text: String) -> Bool {
        var s = String.UnicodeScalarView()
        for u in text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars where u.value != 0xFE0F { s.append(u) }
        return ChatEmojiTables.canonicalNames[String(s)] != nil
    }
}
