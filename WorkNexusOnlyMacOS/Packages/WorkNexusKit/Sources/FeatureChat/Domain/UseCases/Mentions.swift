import Foundation

/// Mention-wire-format helpers: `[@Name](@#userId)` (also a Markdown link).
/// Ported from: lib/core/util/adjacent_mentions.dart + `ParseMessageContent.repairMentions`.
public enum Mentions {
    private static let nested = RX(#"\[\[@([^\]]+)\]\(@#(\d+)\)[^\[\]]*\]\(@#\2\)"#)
    private static let mention = RX(#"\[@([^\]]+)\]\(@#\d+\)"#)
    private static let nameStop = RX(#"[^A-Za-z0-9_]"#)
    private static let adjacentMarkdown = RX(#"(\]\(@#[^)]+\))(?=\[?@)"#)
    /// A run of raw mentions jammed together (`@User1@User2`). Only plain names standing alone: a package
    /// (`@types/node@20`), a fediverse handle or an e-mail continues with `/`, `.domain` or a word before the `@`.
    private static let adjacentAt = RX(#"(?<![\w./@])@[\p{L}\p{N}_]+(?:-[\p{L}\p{N}_]+)*(?:@[\p{L}\p{N}_]+(?:-[\p{L}\p{N}_]+)*)+(?=$|[^\p{L}\p{N}_./@-]|\.(?!\w))"#)

    /// Puts a space between raw mentions jammed together in `text` (`@A@B` → `@A @B`).
    public static func splitAdjacent(_ text: String) -> String {
        adjacentAt.replace(text) { m in
            m.whole.dropFirst().split(separator: "@", omittingEmptySubsequences: false).map { "@\($0)" }.joined(separator: " ")
        }
    }

    /// Undoes what a clumsy sender (or an older client) did to mentions: nested links, a name followed by a stray echo of
    /// itself, and mentions glued to the next one.
    public static func repair(_ text: String) -> String {
        let unwrapped = nested.replace(text) { "[@\($0[1] ?? "")](@#\($0[2] ?? ""))" }
        let ns = unwrapped as NSString
        var out = ""
        var at = 0
        for m in mention.matches(unwrapped) {
            if m.start < at { continue }
            out += ns.substring(with: NSRange(location: at, length: m.end - at))
            at = m.end
            let name = (m[1] ?? "") as NSString
            let cut = nameStop.first(name as String)?.start ?? -1
            if cut > 0 {
                let tail = name.substring(from: cut)
                if ns.length - at >= (tail as NSString).length,
                   ns.substring(with: NSRange(location: at, length: (tail as NSString).length)) == tail {
                    at += name.length - cut
                }
            }
        }
        out += ns.substring(from: at)
        let separated = adjacentMarkdown.replace(out) { "\($0[1] ?? "") " }
        return splitAdjacent(separated)
    }
}
