/// Not in the Flutter app.
import Foundation

/// What a typed search asks for, and where a text answers it: the words of the search must all be there, in any order;
/// words in "quotes" stay together as a phrase. Compared without case or diacritics (`quoc` finds `Quốc`, `duong` finds
/// `Đường`), one character at a time, so a place found in the folded text is the same place in the text as written.
public enum SearchTerms {
    /// `release "phát hành" v2` → `["release", "phát hành", "v2"]`, as typed. A quote left open runs to the end.
    public static func parse(_ query: String) -> [String] {
        var terms: [String] = [], word = "", quoted = false
        func close() {
            let t = word.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { terms.append(t) }
            word = ""
        }
        for c in query {
            if c == "\"" || c == "\u{201C}" || c == "\u{201D}" { close(); quoted.toggle() }
            else if c.isWhitespace, !quoted { close() }
            else { word.append(c) }
        }
        close()
        return terms
    }

    /// A search with its filters taken out: `from:an in:"đội wallet" build` → the text `build` and, per key, the values
    /// given (`from`: `an`; `in`: `đội wallet`). Only `keys` are filters; `http://…` and anything else with a colon
    /// stays in the text. A filter still being typed (`from:`) counts with an empty value.
    public struct Filtered: Equatable, Sendable {
        public var text: String
        public var filters: [String: [String]]
        /// The filter being typed at the end of the search, when there is no space after it yet: its key and what is
        /// typed of its value (to offer names for it).
        public var typing: (key: String, value: String)? {
            guard let last = lastToken, let colon = last.firstIndex(of: ":") else { return nil }
            return (String(last[..<colon]).lowercased(), String(last[last.index(after: colon)...]).replacingOccurrences(of: "\"", with: ""))
        }
        var lastToken: String?
        public static func == (a: Filtered, b: Filtered) -> Bool { a.text == b.text && a.filters == b.filters }
    }

    public static func filters(in query: String, keys: Set<String>) -> Filtered {
        var out = Filtered(text: "", filters: [:]), rest: [String] = []
        // Tokens: runs without spaces, a quoted stretch inside one kept whole (`in:"đội wallet"`).
        var tokens: [String] = [], token = "", quoted = false
        for c in query {
            if c == "\"" || c == "\u{201C}" || c == "\u{201D}" { quoted.toggle(); token.append("\"") }
            else if c.isWhitespace, !quoted { if !token.isEmpty { tokens.append(token); token = "" } }
            else { token.append(c) }
        }
        if !token.isEmpty { tokens.append(token) }
        for t in tokens {
            if let colon = t.firstIndex(of: ":"), keys.contains(t[..<colon].lowercased()) {
                let value = t[t.index(after: colon)...].replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                out.filters[t[..<colon].lowercased(), default: []].append(value)
            } else { rest.append(t) }
        }
        out.text = rest.joined(separator: " ")
        if let last = tokens.last, query.last.map({ !$0.isWhitespace }) ?? false, let colon = last.firstIndex(of: ":"),
           keys.contains(last[..<colon].lowercased()) { out.lastToken = last }
        return out
    }

    /// `query` with the filter being typed at its end replaced by `key:value` (quoted when it has a space) and a space,
    /// ready for the next word.
    public static func completing(_ query: String, key: String, with value: String) -> String {
        var head = query
        while let last = head.last, !last.isWhitespace { head.removeLast() }
        // A quoted value being typed may hold spaces: cut back to the key that opened it.
        if let range = query.range(of: "\(key):", options: [.backwards, .caseInsensitive]) { head = String(query[..<range.lowerBound]) }
        return head + "\(key):" + (value.contains(" ") ? "\"\(value)\"" : value) + " "
    }

    /// One character as the search compares it: lower case, without its diacritics, `đ` as `d`.
    public static func fold(_ c: Character) -> Character {
        if c.isASCII { return Character(c.lowercased()) }
        if c == "đ" || c == "Đ" { return "d" }
        return String(c).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).first ?? c
    }

    /// Where `terms` are found in `text`, in order, touching or overlapping stretches joined. A term that starts a word
    /// somewhere is shown only there (`hanh` in "phát hành", not also inside "thành"); one found only inside words, there.
    public static func ranges(of terms: [String], in text: String) -> [Range<String.Index>] {
        let spans = spans(of: terms, in: text.map(fold))
        guard !spans.isEmpty else { return [] }
        let at = Array(text.indices) + [text.endIndex]
        return spans.map { at[$0.lowerBound]..<at[$0.upperBound] }
    }

    /// How well `text` answers the search, for putting the best first: 0 - the words as typed, in a row, from the start
    /// of a word; 1 - every word starts a word; 2 - anything else (found inside words, or not at all).
    public static func rank(_ terms: [String], in text: String) -> Int {
        let folded = text.map(fold)
        if terms.count > 1, !occurrences(of: terms.joined(separator: " "), in: folded).filter(\.startsWord).isEmpty { return 0 }
        let starts = terms.allSatisfy { !occurrences(of: $0, in: folded).filter(\.startsWord).isEmpty }
        return starts ? (terms.count > 1 ? 1 : 0) : 2
    }

    /// Whether every one of `terms` is found in `text` (none: true).
    public static func allFound(_ terms: [String], in text: String) -> Bool {
        let folded = text.map(fold)
        return terms.allSatisfy { !spans(of: [$0], in: folded).isEmpty }
    }

    /// A stretch of `text` around the first place a term is found, at most about `length` characters, with "…" where it
    /// was cut. The whole text when it is short enough; its start when nothing is found.
    public static func snippet(_ text: String, terms: [String], length: Int = 110) -> String {
        let chars = Array(text)
        guard chars.count > length else { return text }
        let first = spans(of: terms, in: chars.map(fold)).first?.lowerBound ?? 0
        // A third of the room before the match, then back to the start of a word when one is near.
        var start = max(0, first - length / 3)
        if start > 0, let space = chars[max(0, start - 12)..<start].lastIndex(where: \.isWhitespace) { start = space + 1 }
        let end = min(chars.count, start + length)
        if end == chars.count { start = max(0, end - length) }
        return (start > 0 ? "…" : "") + String(chars[start..<end]).trimmingCharacters(in: .whitespaces) + (end < chars.count ? "…" : "")
    }

    private struct Occurrence { var span: Range<Int>; var startsWord: Bool }

    /// Every place `term` is found in already folded characters, with whether a word starts there.
    private static func occurrences(of term: String, in folded: [Character]) -> [Occurrence] {
        let needle = term.map(fold)
        guard !needle.isEmpty, needle.count <= folded.count else { return [] }
        var found: [Occurrence] = [], i = 0
        while i + needle.count <= folded.count {
            if folded[i] == needle[0], folded[i..<(i + needle.count)].elementsEqual(needle) {
                let before = i > 0 ? folded[i - 1] : " "
                found.append(Occurrence(span: i..<(i + needle.count), startsWord: !(before.isLetter || before.isNumber)))
                i += needle.count
            } else { i += 1 }
        }
        return found
    }

    /// The character offsets where `terms` are found in already folded characters, merged: for each term the places it
    /// starts a word, or - when it starts none - every place it is found.
    private static func spans(of terms: [String], in folded: [Character]) -> [Range<Int>] {
        var found: [Range<Int>] = []
        for term in terms {
            let all = occurrences(of: term, in: folded), starts = all.filter(\.startsWord)
            found += (starts.isEmpty ? all : starts).map(\.span)
        }
        var merged: [Range<Int>] = []
        for r in found.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, r.lowerBound <= last.upperBound { merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound) }
            else { merged.append(r) }
        }
        return merged
    }
}
