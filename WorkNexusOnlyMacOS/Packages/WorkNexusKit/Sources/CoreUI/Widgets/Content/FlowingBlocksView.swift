import SwiftUI

/// Not in the Flutter app.
/// `BodyBlocksView` with its text blocks joined (`FlowingBlocks`): one selectable text per run of paragraphs, headings,
/// lists and quotes, so a drag selects across them; code, tables, images and rules sit between the runs as usual.
struct FlowingBlocksView: View {
    @Environment(\.appTheme) private var theme
    let blocks: [BodyBlock]
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let ink: Color
    let images: BodyImageHooks

    var body: some View {
        let typography = theme.typography, size = fontSize
        let flowing = FlowingBlocks(
            heading: { level in typography.font(size: size * BodyBlockView.headingScale[min(level, 6)], weight: .semibold) },
            dim: theme.colors.tx2, gapFont: typography.font(size: theme.spacing.s4))
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            ForEach(Array(flowing.segments(blocks).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    BodyInlineText(text: text, plainFont: typography.font(size: fontSize, weight: .semibold))
                        .font(typography.font(size: fontSize))
                        .foregroundStyle(ink).lineSpacing(max(lineHeight - 1.2, 0) * fontSize)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .block(let block):
                    BodyBlockView(block: block, fontSize: fontSize, lineHeight: lineHeight, ink: ink, images: images)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
