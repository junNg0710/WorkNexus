/// Ported from: lib/features/chat/presentation/widgets/chat_composer_controller.dart (`isOn` / `apply`, here over markdown text)
import Foundation

/// One replacement in the original text; edits of one result never overlap and are sorted by `range.location`.
struct ComposerTextEdit: Equatable, Sendable {
    var range: NSRange
    var replacement: String
}

struct MarkdownFormatResult: Equatable, Sendable {
    var edits: [ComposerTextEdit]
    /// The selection in the text after all `edits`.
    var selection: NSRange
}

/// Applies the toolbar's `MarkdownFormat`s to composer text by adding or removing Markdown markers around the selection (or at
/// the start of its lines). The text always shows what is sent; Quill's hidden attributes are not needed.
enum MarkdownFormatter {
    private static let markers: [MarkdownFormat: (open: String, close: String)] = [
        .bold: ("**", "**"), .italic: ("*", "*"), .underline: ("<u>", "</u>"), .strikethrough: ("~~", "~~"), .code: ("`", "`"),
    ]
    private static let linePrefix = try! NSRegularExpression(pattern: #"^(?:#{1,6} |> |[-*+] |\d+\. )"#)
    private static let listPrefix = try! NSRegularExpression(pattern: #"^(?:[-*+] |\d+\. )"#)

    static func isOn(_ format: MarkdownFormat, text: String, selection: NSRange) -> Bool {
        let s = text as NSString
        guard NSMaxRange(selection) <= s.length else { return false }
        if let mark = markers[format] { return surrounding(format, mark, s, selection) != nil }
        switch format {
        case .heading: return linesOf(s, selection).allSatisfy { s.substring(with: $0).hasPrefix("# ") }
        case .quote: return linesOf(s, selection).allSatisfy { s.substring(with: $0).hasPrefix("> ") }
        case .bulletList: return linesOf(s, selection).allSatisfy { s.substring(with: $0).hasPrefix("- ") }
        case .numberedList:
            return linesOf(s, selection).allSatisfy { numberedLength(s.substring(with: $0)) != nil }
        default: return false
        }
    }

    static func apply(_ format: MarkdownFormat, text: String, selection: NSRange) -> MarkdownFormatResult {
        let s = text as NSString
        let sel = NSRange(location: min(selection.location, s.length), length: min(selection.length, max(0, s.length - selection.location)))
        if let mark = markers[format] { return inline(format, mark, s, sel) }
        switch format {
        case .heading: return lines(s, sel) { _, _ in isOn(.heading, text: text, selection: sel) ? .strip : .set("# ") }
        case .quote: return lines(s, sel) { _, _ in isOn(.quote, text: text, selection: sel) ? .strip : .set("> ") }
        case .bulletList: return lines(s, sel) { _, _ in isOn(.bulletList, text: text, selection: sel) ? .strip : .set("- ") }
        case .numberedList:
            let on = isOn(.numberedList, text: text, selection: sel)
            return lines(s, sel) { _, i in on ? .strip : .set("\(i + 1). ") }
        case .indent: return lines(s, sel) { _, _ in .indent }
        case .outdent: return lines(s, sel) { _, _ in .outdent }
        case .clear: return clear(s, sel)
        default: return MarkdownFormatResult(edits: [], selection: sel)
        }
    }

    // MARK: inline

    /// The marker ranges (before, after) when the selection is wrapped in `mark`, either outside it or inside it.
    private static func surrounding(_ format: MarkdownFormat, _ mark: (open: String, close: String), _ s: NSString, _ sel: NSRange) -> (NSRange, NSRange)? {
        let o = (mark.open as NSString).length, c = (mark.close as NSString).length
        let before = sel.location >= o ? NSRange(location: sel.location - o, length: o) : nil
        let after = NSMaxRange(sel) + c <= s.length ? NSRange(location: NSMaxRange(sel), length: c) : nil
        if let before, let after, s.substring(with: before) == mark.open, s.substring(with: after) == mark.close,
           format != .italic || (starRun(s, endingAt: before.location + o) % 2 == 1 && starRun(s, startingAt: after.location) % 2 == 1) {
            return (before, after)
        }
        if sel.length >= o + c, s.substring(with: NSRange(location: sel.location, length: o)) == mark.open,
           s.substring(with: NSRange(location: NSMaxRange(sel) - c, length: c)) == mark.close,
           format != .italic || (starRun(s, startingAt: sel.location) % 2 == 1) {
            return (NSRange(location: sel.location, length: o), NSRange(location: NSMaxRange(sel) - c, length: c))
        }
        return nil
    }

    private static func starRun(_ s: NSString, endingAt end: Int) -> Int {
        var n = 0
        while end - 1 - n >= 0, s.character(at: end - 1 - n) == 42 { n += 1 }
        return n
    }
    private static func starRun(_ s: NSString, startingAt start: Int) -> Int {
        var n = 0
        while start + n < s.length, s.character(at: start + n) == 42 { n += 1 }
        return n
    }

    private static func inline(_ format: MarkdownFormat, _ mark: (open: String, close: String), _ s: NSString, _ sel: NSRange) -> MarkdownFormatResult {
        let o = (mark.open as NSString).length, c = (mark.close as NSString).length
        if let (b, a) = surrounding(format, mark, s, sel) {
            let edits = [ComposerTextEdit(range: b, replacement: ""), ComposerTextEdit(range: a, replacement: "")]
            let inside = b.location >= sel.location   // markers were part of the selection
            let loc = inside ? sel.location : sel.location - o
            return MarkdownFormatResult(edits: edits, selection: NSRange(location: loc, length: sel.length - (inside ? o + c : 0)))
        }
        // Markers hug the text: spaces at the selection's edges stay outside them.
        var range = sel
        let whitespace = CharacterSet.whitespacesAndNewlines
        while range.length > 0, let u = Unicode.Scalar(s.character(at: range.location)), whitespace.contains(u) { range.location += 1; range.length -= 1 }
        while range.length > 0, let u = Unicode.Scalar(s.character(at: NSMaxRange(range) - 1)), whitespace.contains(u) { range.length -= 1 }
        if range.length == 0 {
            let at = sel.location
            return MarkdownFormatResult(edits: [ComposerTextEdit(range: NSRange(location: at, length: sel.length), replacement: mark.open + mark.close)],
                                        selection: NSRange(location: at + o, length: 0))
        }
        return MarkdownFormatResult(
            edits: [ComposerTextEdit(range: NSRange(location: range.location, length: 0), replacement: mark.open),
                    ComposerTextEdit(range: NSRange(location: NSMaxRange(range), length: 0), replacement: mark.close)],
            selection: NSRange(location: range.location + o, length: range.length))
    }

    // MARK: lines

    private enum LineChange { case strip, set(String), indent, outdent }

    private static func linesOf(_ s: NSString, _ sel: NSRange) -> [NSRange] {
        var out: [NSRange] = []
        var at = s.lineRange(for: NSRange(location: sel.location, length: 0)).location
        let end = max(NSMaxRange(sel), sel.location)
        repeat {
            let r = s.lineRange(for: NSRange(location: at, length: 0))
            out.append(r)
            at = NSMaxRange(r)
        } while at < end && at < s.length
        return out
    }

    private static func numberedLength(_ line: String) -> Int? {
        let ns = line as NSString
        return listPrefix.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)).flatMap { m in
            ns.substring(with: m.range).first?.isNumber == true ? m.range.length : nil
        }
    }

    private static func lines(_ s: NSString, _ sel: NSRange, _ change: (NSRange, Int) -> LineChange) -> MarkdownFormatResult {
        var edits: [ComposerTextEdit] = []
        for (i, r) in linesOf(s, sel).enumerated() {
            let line = s.substring(with: r)
            let ns = line as NSString
            let existing = linePrefix.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))?.range.length ?? 0
            switch change(r, i) {
            case .strip: if existing > 0 { edits.append(.init(range: NSRange(location: r.location, length: existing), replacement: "")) }
            case .set(let p):
                // A line takes one block marker: a new one replaces the old.
                edits.append(.init(range: NSRange(location: r.location, length: existing), replacement: p))
            case .indent: edits.append(.init(range: NSRange(location: r.location, length: 0), replacement: "  "))
            case .outdent:
                var n = 0
                while n < 2, n < ns.length, ns.character(at: n) == 32 { n += 1 }
                if n == 0, ns.length > 0, ns.character(at: 0) == 9 { n = 1 }
                if n > 0 { edits.append(.init(range: NSRange(location: r.location, length: n), replacement: "")) }
            }
        }
        return MarkdownFormatResult(edits: edits, selection: mapSelection(sel, edits))
    }

    private static let inlineMarks = try! NSRegularExpression(pattern: #"\*\*|~~|</?u>|`|(?<![\*\w])\*(?![\*\s])|(?<=\S)\*(?!\*)"#)

    private static func clear(_ s: NSString, _ sel: NSRange) -> MarkdownFormatResult {
        // Block markers on the selected lines, then inline markers inside the selection (all in original coordinates).
        var edits = lines(s, sel) { _, _ in .strip }.edits
        if sel.length > 0 {
            for m in inlineMarks.matches(in: s as String, range: sel) { edits.append(.init(range: m.range, replacement: "")) }
        }
        edits.sort { $0.range.location < $1.range.location }
        return MarkdownFormatResult(edits: edits, selection: mapSelection(sel, edits))
    }

    // MARK: helpers

    static func apply(_ edits: [ComposerTextEdit], to text: String) -> String {
        var s = text as NSString
        for e in edits.reversed() { s = s.replacingCharacters(in: e.range, with: e.replacement) as NSString }
        return s as String
    }

    private static func mapOffset(_ o: Int, _ edits: [ComposerTextEdit]) -> Int {
        var shift = 0
        for e in edits {
            let replaced = (e.replacement as NSString).length
            if o >= NSMaxRange(e.range) { shift += replaced - e.range.length }
            else if o > e.range.location { return e.range.location + shift + replaced }
            else { break }
        }
        return o + shift
    }

    private static func mapSelection(_ sel: NSRange, _ edits: [ComposerTextEdit]) -> NSRange {
        let a = mapOffset(sel.location, edits), b = mapOffset(NSMaxRange(sel), edits)
        return NSRange(location: a, length: max(0, b - a))
    }
}
