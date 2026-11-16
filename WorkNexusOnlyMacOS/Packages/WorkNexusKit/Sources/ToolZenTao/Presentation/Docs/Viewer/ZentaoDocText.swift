/// Ported from: lib/tools/zentao/presentation/widgets/{zentao_doc_inline,zentao_doc_body}.dart (the find marks, inline code
/// chips, link colour and heading rhythm of the page's text)
import CoreUI
import SwiftUI

enum ZentaoDocText {
    /// The highlight behind a find match: soft for every match, strong for the current one.
    static func findFill(_ theme: AppTheme, current: Bool) -> Color { theme.colors.amber.opacity(current ? 0.55 : 0.22) }

    /// `runs` as one attributed string: emphasis, links in the accent, inline code as a mono chip, and the find matches
    /// on a highlight (the `current` one strongest).
    static func attributed(_ runs: [ZentaoRun], theme: AppTheme, size: CGFloat, current: Int) -> AttributedString {
        var out = AttributedString()
        for r in runs {
            var a = AttributedString(r.text)
            var intent: InlinePresentationIntent = []
            if r.bold { intent.insert(.stronglyEmphasized) }
            if r.italic { intent.insert(.emphasized) }
            if !intent.isEmpty { a.inlinePresentationIntent = intent }
            if r.code {
                a.font = .custom("Space Mono", size: size * 0.88)
                a.backgroundColor = theme.colors.panel2
            }
            if r.underline { a.underlineStyle = .single }
            if r.strike { a.strikethroughStyle = .single }
            if let link = r.link, let url = URL(string: link) { a.link = url; a.foregroundColor = theme.colors.accent }
            // A colour the document sets (`font` / `span` / `style`) wins over the link's accent, as it does on the web.
            if let color = r.color { a.foregroundColor = color.color }
            if let bg = r.background { a.backgroundColor = bg.color }
            if let script = r.script {
                a.baselineOffset = size * (script == .sup ? 0.35 : -0.2)
                a.font = .system(size: size * 0.75, weight: r.bold ? .semibold : .regular)
            }
            if let find = r.find { a.backgroundColor = findFill(theme, current: find == current) }
            out.append(a)
        }
        return out
    }

    /// Heading sizes by level (`h1`...`h6`), as the document page sets them.
    static func headingSize(_ level: Int) -> CGFloat {
        switch level { case 1: 28; case 2: 24; case 3: 20; case 4: 17; default: 16 }
    }

    /// Air above a heading: more than below, so a section reads as belonging to what follows.
    static func spaceAbove(_ level: Int, _ theme: AppTheme) -> CGFloat {
        switch level { case 1, 2: theme.spacing.s40; case 3, 4: theme.spacing.s24; default: theme.spacing.s20 }
    }
}

/// A paragraph or heading of the page. Only a block holding find matches reads the reader's current match, so stepping
/// through results doesn't redraw the rest of the page.
struct ZentaoDocTextBlock: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.zentaoDocAlign) private var align
    let runs: [ZentaoRun]; let level: Int; let reader: ZentaoDocReader; let color: Color?

    var body: some View {
        let current = runs.contains { $0.find != nil } ? reader.current : -1
        let size = level > 0 ? ZentaoDocText.headingSize(level) : theme.typography.proseSize
        Text(ZentaoDocText.attributed(runs, theme: theme, size: size, current: current))
            .font(theme.typography.font(size: size, weight: level > 0 ? .semibold : .regular))
            .foregroundStyle(color ?? theme.colors.tx)
            .lineSpacing(level > 0 ? size * 0.2 : size * 0.45)
            .multilineTextAlignment(align.text)
            .frame(maxWidth: .infinity, alignment: align.alignment)
    }
}

extension AppTypography {
    /// The reading size of a document's text (`prose`).
    var proseSize: CGFloat { 15 }
}
