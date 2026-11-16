/// Ported from: lib/features/workspace_overview/presentation/widgets/{dashboard_card,dashboard_grid}.dart
import CoreUI
import SwiftUI

/// A dashboard section in the app's panel-card style: a surface with a hairline border, a header with an icon, count
/// and optional action, then the content. Rows reach the edge when `inset` is small.
struct DashboardCard<Action: View, Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let systemImage: String
    var count: Int?
    var padding: EdgeInsets?
    let action: Action
    let content: Content

    init(title: String, systemImage: String, count: Int? = nil, padding: EdgeInsets? = nil,
         @ViewBuilder action: () -> Action = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title; self.systemImage = systemImage; self.count = count; self.padding = padding
        self.action = action(); self.content = content()
    }

    var body: some View {
        let s = theme.spacing
        CardSurface {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: s.s8) {
                    Image(systemName: systemImage).font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.tx2)
                    Text(title).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                    if let count { AppCountBadge(count) }
                    Spacer(minLength: 0)
                    action
                }
                .padding(EdgeInsets(top: s.s12, leading: s.s12, bottom: 0, trailing: s.s8))
                content.padding(padding ?? EdgeInsets(top: s.s12, leading: s.s12, bottom: s.s12, trailing: s.s12))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// A text-button action for a card header ("Show all").
struct CardHeaderAction: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let onTap: () -> Void

    var body: some View {
        HoverSurface(onTap: onTap, cornerRadius: theme.radii.sm) {
            Text(title).font(theme.typography.caption.weight(.semibold)).foregroundStyle(theme.colors.accent)
                .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s4)
        }
    }
}

/// One cell of a `DashboardGrid`.
struct DashboardCell: Identifiable {
    let id: String
    let view: AnyView
    init<V: View>(_ id: String, _ view: V) { self.id = id; self.view = AnyView(view) }
}

/// Dashboard cards two per row when `wide` - the cards of a row share the taller one's height - else one column.
/// An odd last card takes the full width.
struct DashboardGrid: View {
    @Environment(\.appTheme) private var theme
    let wide: Bool
    let cells: [DashboardCell]

    var body: some View {
        VStack(spacing: theme.spacing.s12) {
            if wide {
                ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { i in
                    if i + 1 < cells.count {
                        HStack(alignment: .top, spacing: theme.spacing.s12) {
                            cells[i].view.frame(maxWidth: .infinity, maxHeight: .infinity)
                            cells[i + 1].view.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        cells[i].view
                    }
                }
            } else {
                ForEach(cells) { $0.view }
            }
        }
    }
}
