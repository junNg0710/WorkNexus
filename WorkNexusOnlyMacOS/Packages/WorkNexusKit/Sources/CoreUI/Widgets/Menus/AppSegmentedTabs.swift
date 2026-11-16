import SwiftUI

/// Ported from: lib/core/widgets/app_segmented_tabs.dart
/// One segment of `AppSegmentedTabs`.
public struct AppSegmentedTab: Identifiable {
    public let id = UUID()
    public var label: String
    public var active: Bool
    public var onTap: () -> Void
    /// Shown beside the label when set.
    public var count: Int?
    /// Shows a spinner in place of the count while the tab's view loads.
    public var loading: Bool
    /// SF Symbol shown before the label when set.
    public var icon: String?

    public init(label: String, active: Bool, count: Int? = nil, loading: Bool = false, icon: String? = nil, onTap: @escaping () -> Void) {
        self.label = label; self.active = active; self.count = count; self.loading = loading; self.icon = icon; self.onTap = onTap
    }
}

/// View tabs (All / Unclosed, Issues / Merge Requests…) as a segmented control: the active segment is raised on
/// an inset track, at the toolbar's control height, with an optional count (or a spinner while it loads).
/// `iconOnly` draws a tab that has an icon as the icon alone, its label as a tooltip.
public struct AppSegmentedTabs: View {
    @Environment(\.appTheme) private var theme
    let tabs: [AppSegmentedTab]; let iconOnly: Bool
    public init(_ tabs: [AppSegmentedTab], iconOnly: Bool = false) { self.tabs = tabs; self.iconOnly = iconOnly }

    public var body: some View {
        HStack(spacing: 0) { ForEach(tabs) { SegmentView(tab: $0, iconOnly: iconOnly) } }
            .padding(theme.spacing.s2).frame(height: theme.sizes.control32)
            .appGlass(in: RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous), fallback: theme.colors.panel2)
    }
}

private struct SegmentView: View {
    @Environment(\.appTheme) private var theme
    let tab: AppSegmentedTab; let iconOnly: Bool
    var body: some View {
        let ink = tab.active ? theme.colors.tx : theme.colors.tx2
        HoverSurface(onTap: tab.onTap, selected: false, fill: tab.active ? theme.colors.card : .clear,
                     border: tab.active ? theme.colors.line : nil, cornerRadius: theme.radii.sm) {
            HStack(spacing: theme.spacing.s6) {
                if let icon = tab.icon { Image(systemName: icon).font(.system(size: theme.sizes.icon14)).foregroundStyle(ink) }
                if !(iconOnly && tab.icon != nil) {
                    // One weight for both states, so switching tabs moves nothing.
                    Text(tab.label).font(theme.typography.label).foregroundStyle(ink).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    if tab.loading { ProgressView().controlSize(.mini) }
                    else if let count = tab.count { AppCountBadge(count) }
                }
            }
            .padding(.horizontal, theme.spacing.s12).frame(maxHeight: .infinity)
        }
        .help(iconOnly && tab.icon != nil ? tab.label : "")
    }
}
