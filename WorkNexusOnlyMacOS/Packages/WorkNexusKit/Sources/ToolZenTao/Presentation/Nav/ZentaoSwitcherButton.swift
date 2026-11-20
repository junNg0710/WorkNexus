import CoreUI
import SwiftUI

/// Ported from: lib/tools/zentao/presentation/widgets/zentao_execution_switcher.dart
/// The header's breadcrumb quick-switcher (`Project › Execution ▾`): a folder icon, what `kind` of thing is open,
/// its `title`, and a chevron; it opens `popover` (given a way to close it) below itself.
struct ZentaoSwitcherButton<Popover: View>: View {
    @Environment(\.appTheme) private var theme
    @State private var open = false
    let kind: String
    let title: String
    let popover: (_ close: @escaping () -> Void) -> Popover

    var body: some View {
        let c = theme.colors
        HoverSurface(onTap: { open.toggle() }, cornerRadius: theme.radii.sm) {
            HStack(spacing: theme.spacing.s4) {
                Image(systemName: "folder").font(.system(size: theme.sizes.icon14)).foregroundStyle(c.accent)
                Text(kind).font(theme.typography.meta).foregroundStyle(c.tx2)
                Text(verbatim: "›").font(theme.typography.meta).foregroundStyle(c.tx3)
                Text(title).font(theme.typography.metaStrong).foregroundStyle(c.tx).lineLimit(1)
                    .frame(maxWidth: theme.sizes.detailPanel / 2)
                Image(systemName: "chevron.down").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.tx2)
            }
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s4)
        }
        .fixedSize()
        .popover(isPresented: $open, arrowEdge: .bottom) { popover { open = false } }
    }
}
