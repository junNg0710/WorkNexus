import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/shell_pane/{sidebar_primitives,sidebar_tree_rows,provider_pinned_projects}.dart
/// Children of a tree node, indented under a vertical guide line.
public struct SidebarTreeBranch<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let strong: Bool; let content: Content
    public init(strong: Bool = false, @ViewBuilder content: () -> Content) { self.strong = strong; self.content = content() }
    public var body: some View {
        content.padding(.leading, theme.spacing.s8)
            .overlay(alignment: .leading) { Rectangle().fill(strong ? theme.colors.line2 : theme.colors.line).frame(width: 1) }
            .padding(.leading, theme.spacing.s8).padding(.top, theme.spacing.s2)
    }
}

public struct SidebarPinButton: View {
    @Environment(\.appTheme) private var theme
    let pinned: Bool; let tooltip: String; let onTap: () -> Void
    public init(pinned: Bool, tooltip: String, onTap: @escaping () -> Void) { self.pinned = pinned; self.tooltip = tooltip; self.onTap = onTap }
    public var body: some View {
        Button(action: onTap) {
            Image(systemName: pinned ? "pin.fill" : "pin").font(.system(size: theme.sizes.icon12)).foregroundStyle(pinned ? theme.colors.accent : theme.colors.tx3)
                .frame(width: theme.sizes.icon20, height: theme.sizes.icon20)
        }
        .buttonStyle(.plain).help(tooltip)
    }
}

public struct SidebarSyncIndicator: View {
    public init() {}
    public var body: some View { ProgressView().controlSize(.mini).frame(width: 21, height: 21) }
}

public struct SidebarPinnedHeader: View {
    @Environment(\.appTheme) private var theme
    public init() {}
    public var body: some View {
        HStack(spacing: theme.spacing.s4) {
            Image(systemName: "pin.fill").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.accent)
            Text(appString("pinned", "Pinned").uppercased()).font(theme.typography.sidebarGroupLabel).foregroundStyle(theme.colors.tx2).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.spacing.s6).frame(height: theme.sizes.control32 - theme.spacing.s6)
    }
}

/// The "assigned to me" count badge of a tree node (hidden at 0).
public struct SidebarCountBadge: View {
    let count: Int
    public init(_ count: Int) { self.count = count }
    public var body: some View {
        if count > 0 { AppCountBadge(count).help(appString("assignedToMe", "Assigned to me")) }
    }
}

/// A collapsible group header (chevron, optional icon, label, count).
public struct SidebarGroupToggle: View {
    @Environment(\.appTheme) private var theme
    @State private var hovered = false
    let label: String; let expanded: Bool; var systemImage: String?; var count: Int?; let onTap: () -> Void
    public init(label: String, expanded: Bool, systemImage: String? = nil, count: Int? = nil, onTap: @escaping () -> Void) {
        self.label = label; self.expanded = expanded; self.systemImage = systemImage; self.count = count; self.onTap = onTap
    }
    public var body: some View {
        let c = theme.colors
        Button(action: onTap) {
            HStack(spacing: theme.spacing.s4) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.tx3)
                if let systemImage { Image(systemName: systemImage).font(.system(size: theme.sizes.icon14)).foregroundStyle(c.tx3) }
                Text(label).font(theme.typography.sidebarGroupLabel).foregroundStyle(c.tx2).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if let count { SidebarCountBadge(count) }
            }
            .padding(.horizontal, theme.spacing.s6).frame(height: theme.sizes.control32 - theme.spacing.s6)
            .background(hovered ? c.panel2 : .clear, in: RoundedRectangle(cornerRadius: theme.radii.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovered = $0 }.pointerStyle(.link)
    }
}

/// "Loading…" / error / quiet note row inside a tree, with optional retry.
public struct SidebarStatusRow: View {
    @Environment(\.appTheme) private var theme
    let label: String; var loading: Bool; var isError: Bool; var onRetry: (() -> Void)?
    public init(label: String, loading: Bool = false, isError: Bool = false, onRetry: (() -> Void)? = nil) {
        self.label = label; self.loading = loading; self.isError = isError; self.onRetry = onRetry
    }
    public var body: some View {
        let ink = isError ? theme.colors.red : theme.colors.tx3
        HStack(spacing: theme.spacing.s6) {
            if loading { ProgressView().controlSize(.mini) }
            else if isError { Image(systemName: "exclamationmark.circle").font(.system(size: theme.sizes.icon12)).foregroundStyle(ink) }
            else { Circle().fill(ink).frame(width: theme.spacing.s4, height: theme.spacing.s4) }
            Text(label).font(theme.typography.mono.weight(.medium)).foregroundStyle(ink).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if let onRetry { AppIconButton("arrow.clockwise", help: appString("retry", "Retry"), action: onRetry) }
        }
        .padding(.leading, theme.spacing.s6).frame(height: theme.sizes.control32 - theme.spacing.s6)
    }
}

/// The pinned projects of a provider under a "Pinned" header; `rowBuilder` renders one project.
public struct ProviderPinnedProjects<Row: View>: View {
    @Environment(\.appTheme) private var theme
    let pinned: [ProviderProject]; let rowBuilder: (ProviderProject) -> Row
    public init(pinned: [ProviderProject], @ViewBuilder rowBuilder: @escaping (ProviderProject) -> Row) { self.pinned = pinned; self.rowBuilder = rowBuilder }
    public var body: some View {
        if !pinned.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SidebarPinnedHeader()
                ForEach(pinned) { rowBuilder($0) }
            }
            .padding(.bottom, theme.spacing.s4)
        }
    }
}
