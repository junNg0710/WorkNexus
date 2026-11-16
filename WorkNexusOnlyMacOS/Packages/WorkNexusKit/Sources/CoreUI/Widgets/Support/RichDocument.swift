import Foundation

/// Ported from: flutter_quill `Document`/`Delta` as used by lib/core/widgets/html_editing_controller.dart.
/// A flat, AppKit-free rich-text model: lines of attributed runs. Inline attributes live on runs, block
/// attributes (heading, list, quote, code, alignment, indent) on lines — the same split Quill makes between
/// text ops and the `\n` that ends a line. An image is a one-character run (`\u{FFFC}`) carrying its URL.
public enum RichListKind: String, Sendable, Equatable { case bullet, ordered }

/// Character attributes of a run.
public struct RichInline: Equatable, Sendable {
    public var bold = false, italic = false, underline = false, strike = false, code = false
    /// `#rrggbb` (or any CSS colour string as written).
    public var color: String?
    public var background: String?
    public var link: String?
    /// Set on the single `\u{FFFC}` character of an inline image.
    public var image: String?
    /// Pixel width of an image (Quill keeps it in its `style`; ZenTao reads `width`).
    public var imageWidth: String?
    public init() {}
}

/// Paragraph attributes of a line.
public struct RichBlock: Equatable, Sendable {
    public var header: Int?
    public var list: RichListKind?
    public var blockquote = false
    public var codeBlock = false
    public var align: String?
    public var indent = 0
    public init() {}
    public var isPlain: Bool { self == RichBlock() }
}

public struct RichRun: Equatable, Sendable {
    public var text: String
    public var inline: RichInline
    public init(_ text: String, _ inline: RichInline = RichInline()) { self.text = text; self.inline = inline }
    public static let imageChar = "\u{FFFC}"
    public static func image(_ url: String, width: String? = nil) -> RichRun {
        var i = RichInline(); i.image = url; i.imageWidth = width
        return RichRun(imageChar, i)
    }
}

public struct RichLine: Equatable, Sendable {
    public var runs: [RichRun]
    public var block: RichBlock
    public init(runs: [RichRun] = [], block: RichBlock = RichBlock()) { self.runs = runs; self.block = block }
    public var text: String { runs.map(\.text).joined() }
    /// UTF-16 length without the line break.
    public var length: Int { runs.reduce(0) { $0 + $1.text.utf16.count } }
    public var hasEmbed: Bool { runs.contains { $0.inline.image != nil } }
}

public struct RichDocument: Equatable, Sendable {
    public private(set) var lines: [RichLine]

    /// An empty document: one empty line (Quill's `"\n"`).
    public init() { lines = [RichLine()] }
    public init(lines: [RichLine]) {
        var l = lines.map { RichDocument.normalized($0) }
        if l.isEmpty { l = [RichLine()] }
        self.lines = l
    }

    /// Plain text, lines separated and ended by `\n` (an image reads as `\u{FFFC}`).
    public var plainText: String { lines.map { $0.text + "\n" }.joined() }
    /// UTF-16 length including one break per line.
    public var length: Int { lines.reduce(0) { $0 + $1.length + 1 } }
    public var hasEmbeds: Bool { lines.contains(where: \.hasEmbed) }

    static func normalized(_ line: RichLine) -> RichLine {
        var out: [RichRun] = []
        for r in line.runs where !r.text.isEmpty {
            if let last = out.last, last.inline == r.inline, r.inline.image == nil {
                out[out.count - 1].text += r.text
            } else { out.append(r) }
        }
        return RichLine(runs: out, block: line.block)
    }

    /// Inserts `text` (which may hold `\n`) at a UTF-16 `offset`. A split line keeps its block attributes on
    /// the first half, as pressing Return in a list item does.
    public mutating func insert(_ text: String, at offset: Int, inline: RichInline = RichInline()) {
        let (li, within) = locate(offset)
        let line = lines[li]
        let (head, tail) = Self.split(line.runs, at: within)
        let pieces = text.components(separatedBy: "\n")
        var newLines: [RichLine] = []
        var currentHead = head
        for (i, piece) in pieces.enumerated() {
            if !piece.isEmpty { currentHead.append(RichRun(piece, inline)) }
            if i < pieces.count - 1 {
                newLines.append(Self.normalized(RichLine(runs: currentHead, block: line.block)))
                currentHead = []
            }
        }
        newLines.append(Self.normalized(RichLine(runs: currentHead + tail, block: line.block)))
        lines.replaceSubrange(li...li, with: newLines)
    }

    /// Puts an image run at `offset` (Quill: `replaceText(at, 0, BlockEmbed.image(url))`).
    public mutating func insertImage(_ url: String, width: String? = nil, at offset: Int) {
        let (li, within) = locate(offset)
        let (head, tail) = Self.split(lines[li].runs, at: within)
        lines[li].runs = Self.normalized(RichLine(runs: head + [.image(url, width: width)] + tail)).runs
    }

    /// Changes the inline attributes of `[offset, offset + length)` (an inline-range `formatText`).
    public mutating func formatText(at offset: Int, length: Int, _ change: (inout RichInline) -> Void) {
        var pos = 0
        for li in lines.indices {
            var runs: [RichRun] = []
            for run in lines[li].runs {
                let len = run.text.utf16.count
                let lo = max(offset - pos, 0), hi = min(offset + length - pos, len)
                if lo < hi, run.inline.image != nil || !run.text.isEmpty {
                    let (a, rest) = Self.splitRun(run, at: lo)
                    let (mid, b) = Self.splitRun(rest, at: hi - lo)
                    var m = mid; change(&m.inline)
                    runs += [a, m, b].filter { !$0.text.isEmpty }
                } else { runs.append(run) }
                pos += len
            }
            lines[li] = Self.normalized(RichLine(runs: runs, block: lines[li].block))
            pos += 1
        }
    }

    /// Changes the block attributes of the line holding `offset`.
    public mutating func formatLine(at offset: Int, _ change: (inout RichBlock) -> Void) {
        let (li, _) = locate(offset)
        change(&lines[li].block)
    }

    // MARK: offsets

    private func locate(_ offset: Int) -> (line: Int, within: Int) {
        var rest = max(offset, 0)
        for (i, l) in lines.enumerated() {
            if rest <= l.length { return (i, rest) }
            rest -= l.length + 1
        }
        return (lines.count - 1, lines[lines.count - 1].length)
    }

    private static func splitRun(_ run: RichRun, at utf16: Int) -> (RichRun, RichRun) {
        if utf16 <= 0 { return (RichRun("", run.inline), run) }
        if utf16 >= run.text.utf16.count { return (run, RichRun("", run.inline)) }
        let i = String.Index(utf16Offset: utf16, in: run.text)
        return (RichRun(String(run.text[..<i]), run.inline), RichRun(String(run.text[i...]), run.inline))
    }

    private static func split(_ runs: [RichRun], at offset: Int) -> ([RichRun], [RichRun]) {
        var head: [RichRun] = [], tail: [RichRun] = [], pos = 0
        for r in runs {
            let len = r.text.utf16.count
            if pos + len <= offset { head.append(r) }
            else if pos >= offset { tail.append(r) }
            else {
                let (a, b) = splitRun(r, at: offset - pos)
                head.append(a); tail.append(b)
            }
            pos += len
        }
        return (head, tail)
    }
}
