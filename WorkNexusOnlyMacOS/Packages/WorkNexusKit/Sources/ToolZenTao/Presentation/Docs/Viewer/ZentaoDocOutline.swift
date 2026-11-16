/// Ported from: lib/tools/zentao/presentation/widgets/zentao_doc_outline.dart
import CoreUI
import SwiftUI

/// "On this page": the document's headings beside it, nested by level along a rail, the one being read lit on the rail.
/// A tap scrolls to a heading.
struct ZentaoDocOutline: View {
    @Environment(\.appTheme) private var theme
    let headings: [ZentaoDocHeading]; let reader: ZentaoDocReader
    /// Called after a heading is picked (the popover closes on it).
    var onPicked: (() -> Void)?

    var body: some View {
        let top = headings.map(\.level).min() ?? 1
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(appString("docsOutline", "On this page")).font(theme.typography.label).foregroundStyle(theme.colors.tx3)
                    .padding(.leading, theme.spacing.s12).padding(.bottom, theme.spacing.s8)
                ForEach(headings, id: \.index) { h in
                    ZentaoDocOutlineEntry(heading: h, depth: h.level - top, active: h.index == reader.activeHeading) {
                        reader.goToHeading(h.index)
                        onPicked?()
                    }
                }
            }
            .padding(EdgeInsets(top: theme.spacing.s12, leading: theme.spacing.s8, bottom: theme.spacing.s12, trailing: theme.spacing.s12))
        }
        .scrollIndicators(.never)
    }
}

private struct ZentaoDocOutlineEntry: View {
    @Environment(\.appTheme) private var theme
    @State private var hovered = false
    let heading: ZentaoDocHeading; let depth: Int; let active: Bool; let onTap: () -> Void

    var body: some View {
        let c = theme.colors
        // Hover lights the line and its stretch of the rail, the way the lit entry is drawn.
        Button(action: onTap) {
            Text(heading.text).lineLimit(1)
                .font(theme.typography.paragraph.weight(active ? .semibold : .regular))
                .foregroundStyle(active || hovered ? c.tx : c.tx2)
                .padding(.leading, theme.spacing.s12 + theme.spacing.s16 * CGFloat(depth))
                .padding(.vertical, theme.spacing.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    // The rail: a hairline down the list, the reader's place on it lit.
                    Rectangle().fill(active ? c.accent : (hovered ? c.tx3 : c.line))
                        .frame(width: active ? theme.borders.thick : theme.borders.hairline)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovered = $0 }.pointerStyle(.link)
    }
}

/// The outline in a popover, for a window too narrow to keep it beside the page.
struct ZentaoDocOutlineButton: View {
    @State private var open = false
    let headings: [ZentaoDocHeading]; let reader: ZentaoDocReader

    var body: some View {
        ZentaoDocToolButton(systemImage: "list.bullet.indent", help: appString("docsOutline", "On this page"), selected: open) { open.toggle() }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                ZentaoDocOutline(headings: headings, reader: reader) { open = false }.frame(width: 300, height: 440)
            }
    }
}
