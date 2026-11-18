import SwiftUI

/// Not in the Flutter app.
/// Joins the blocks of a body that read as text (paragraphs, headings, lists and quotes of those) into one attributed
/// text, so a drag can select across all of them: each selectable `Text` keeps its own selection, so a message drawn as
/// one view per paragraph could only be picked a paragraph at a time. Code, tables, images and rules stay blocks of
/// their own between the joined runs.
public struct FlowingBlocks {
    public enum Segment: Equatable {
        case text(AttributedString)
        case block(BodyBlock)
    }

    /// The font of a heading of `level` (1…6); paragraphs keep the font of the view.
    let heading: (Int) -> Font
    /// Ink of quotes and of the quote bar.
    let dim: Color?
    /// The font of the blank line between two joined blocks: its size sets the gap.
    let gapFont: Font?

    public init(heading: @escaping (Int) -> Font, dim: Color? = nil, gapFont: Font? = nil) {
        self.heading = heading; self.dim = dim; self.gapFont = gapFont
    }

    public func segments(_ blocks: [BodyBlock]) -> [Segment] {
        var out: [Segment] = []
        var run: [AttributedString] = []
        func flush() {
            guard !run.isEmpty else { return }
            out.append(.text(run.dropFirst().reduce(into: run[0]) { all, next in all += gap; all += next }))
            run = []
        }
        for block in blocks {
            if let lines = lines(block, depth: 0) { run.append(joined(lines.map(\.text))) } else { flush(); out.append(.block(block)) }
        }
        flush()
        return out
    }

    /// A line of joined text; `indented` once a list has put its own indent and marker in front of it.
    private struct Line { var text: AttributedString; var indented: Bool }

    private func lines(_ block: BodyBlock, depth: Int) -> [Line]? {
        switch block {
        case .text(let s, let level):
            var text = s
            if level > 0 { text.font = heading(level) }
            return [Line(text: text, indented: false)]
        case .list(let ordered, let start, let items):
            var out: [Line] = []
            let indent = String(repeating: "    ", count: depth)
            for (i, item) in items.enumerated() {
                var first = true
                for child in item {
                    guard let inner = lines(child, depth: depth + 1) else { return nil }
                    for line in inner {
                        if line.indented { out.append(line); continue }
                        let lead = indent + (first ? (ordered ? "\(start + i). " : "•  ") : "    ")
                        out.append(Line(text: marker(lead) + line.text, indented: true))
                        first = false
                    }
                }
            }
            return out
        case .quote(let inner):
            var out: [Line] = []
            for child in inner {
                guard let quoted = lines(child, depth: depth) else { return nil }
                out += quoted.map { Line(text: marker("▍ ") + dimmed($0.text), indented: $0.indented) }
            }
            return out
        case .image, .code, .table, .rule:
            return nil
        }
    }

    private func marker(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        if let dim { a.foregroundColor = dim }
        return a
    }

    /// Quote ink on everything but its links (they keep the link colour).
    private func dimmed(_ text: AttributedString) -> AttributedString {
        guard let dim else { return text }
        var out = text
        for run in out.runs where run.link == nil { out[run.range].foregroundColor = dim }
        return out
    }

    private func joined(_ parts: [AttributedString]) -> AttributedString {
        parts.dropFirst().reduce(into: parts.first ?? AttributedString()) { all, next in all += AttributedString("\n"); all += next }
    }

    /// A line break, then a short blank line standing in for the space between two blocks.
    private var gap: AttributedString {
        var blank = AttributedString("\n")
        if let gapFont { blank.font = gapFont }
        return AttributedString("\n") + blank
    }
}
