/// Ported from: lib/tools/zentao/presentation/widgets/zentao_doc_code_block.dart
import CoreUI
import SwiftUI

/// A code block in a ZenTao document, as ZenTao's web shows one: numbered lines that never wrap - documents hold ASCII
/// diagrams and aligned tables whose columns a wrap would break - scrolling sideways when wider than the page, with a
/// copy button in the corner. Find `matches` in it are highlighted, the reader's `current` one strongest.
struct ZentaoDocCodeBlock: View {
    @Environment(\.appTheme) private var theme
    let code: String; let fontSize: CGFloat
    var matches: [ZentaoFindRange] = []
    var reader: ZentaoDocReader?

    var body: some View {
        let c = theme.colors
        let lines = code.components(separatedBy: "\n")
        let font = Font.custom("Space Mono", size: fontSize)
        let spacing = fontSize * 0.6
        let current = matches.isEmpty ? -1 : (reader?.current ?? -1)
        HStack(alignment: .top, spacing: 0) {
            // The gutter: its own tinted band, ruled off from the code, so the numbers don't read as part of it.
            Text((1...max(lines.count, 1)).map(String.init).joined(separator: "\n"))
                .font(font).lineSpacing(spacing).foregroundStyle(c.tx3).multilineTextAlignment(.trailing)
                .textSelection(.disabled)
                .padding(EdgeInsets(top: theme.spacing.s10, leading: theme.spacing.s10, bottom: theme.spacing.s10, trailing: theme.spacing.s8))
                .frame(maxHeight: .infinity, alignment: .top)
                .background(c.panel)
                .overlay(alignment: .trailing) { Rectangle().fill(c.line).frame(width: theme.borders.hairline) }
            ScrollView(.horizontal) {
                Text(highlighted(current: current)).font(font).lineSpacing(spacing).foregroundStyle(c.tx)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(EdgeInsets(top: theme.spacing.s10, leading: theme.spacing.s8, bottom: theme.spacing.s10, trailing: theme.spacing.s40))
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.panel2)
        .overlay(alignment: .topTrailing) { CodeCopyButton(code: code).padding(theme.spacing.s4) }
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.sm))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.sm).stroke(c.line, lineWidth: theme.borders.hairline))
    }

    /// The code with its find matches on a highlight.
    private func highlighted(current: Int) -> AttributedString {
        var a = AttributedString(code)
        for m in matches {
            let ns = NSRange(location: m.start, length: max(m.end - m.start, 0))
            if let r = Range(ns, in: a) { a[r].backgroundColor = ZentaoDocText.findFill(theme, current: m.index == current) }
        }
        return a
    }
}
