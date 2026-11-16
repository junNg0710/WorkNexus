/// Ported from: lib/tools/zentao/presentation/nav/zentao_doc_tree_row.dart
import CoreUI
import SharedKit
import SwiftUI

/// One row of the Docs tree: a library (with a chevron, `expanded` non-nil) or a document (`indented` under its
/// library). The pin shows while the row is hovered, and stays for a pinned row, so 150 libraries don't each carry a
/// pin glyph.
struct ZentaoDocTreeRow: View {
    @Environment(\.appTheme) private var theme
    let systemImage: String; let label: String
    var subtitle: String?
    let onTap: () -> Void
    let pinned: Bool; let pinTooltip: String; let onPin: () -> Void
    /// A library's open state; nil for a document (no chevron).
    var expanded: Bool?
    var indented = false
    var selected = false

    var body: some View {
        let c = theme.colors
        // A document lines up under its library's icon, past the chevron.
        let indent = indented ? theme.sizes.icon14 + theme.spacing.s4 : 0
        HoverRegion { hovered in
            HoverSurface(onTap: onTap, selected: selected, height: nil, fill: selected ? c.sel : .clear, cornerRadius: theme.radii.sm) {
                HStack(spacing: 0) {
                    if let expanded {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: theme.sizes.icon12))
                            .foregroundStyle(c.tx3).frame(width: theme.sizes.icon14).padding(.trailing, theme.spacing.s4)
                    }
                    Image(systemName: systemImage).font(.system(size: theme.sizes.icon14)).foregroundStyle(selected ? c.accent : c.tx3)
                        .frame(width: theme.sizes.icon16).padding(.trailing, theme.spacing.s6)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(label).lineLimit(1).font(theme.typography.meta.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? c.accent : c.tx)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle).lineLimit(1).font(theme.typography.caption).foregroundStyle(c.tx3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Room kept for the pin, so the label doesn't reflow on hover.
                    SidebarPinButton(pinned: pinned, tooltip: pinTooltip, onTap: onPin).opacity(hovered || pinned ? 1 : 0)
                }
                .padding(EdgeInsets(top: theme.spacing.s2, leading: theme.spacing.s6 + indent, bottom: theme.spacing.s2, trailing: theme.spacing.s4))
                .frame(minHeight: theme.sizes.control32 - theme.spacing.s4)
            }
        }
    }
}
