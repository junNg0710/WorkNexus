import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/shell_pane/scope_rows.dart (`ScopeQuickRow`, `ScopeGroupHeader`, `ScopeRow` → `ScopeEntryRow`).
/// (`ScopeRow` in `ShellPaneKit.swift` is the simpler generic row the shell itself uses.)

/// The type style of group headers in the sidebar (mono, semi-bold, secondary ink).
public extension AppTypography {
    var sidebarGroupLabel: Font { mono.weight(.semibold) }
}

/// A "quick scope" row (Assigned to me, Recent…) with an optional icon and count.
public struct ScopeQuickRow: View {
    @Environment(\.appTheme) private var theme
    let label: String; var systemImage: String?; var count: Int?; var selected: Bool; let onTap: () -> Void
    public init(label: String, systemImage: String? = nil, count: Int? = nil, selected: Bool = false, onTap: @escaping () -> Void) {
        self.label = label; self.systemImage = systemImage; self.count = count; self.selected = selected; self.onTap = onTap
    }
    public var body: some View {
        let c = theme.colors
        HoverSurface(onTap: onTap, selected: selected, height: theme.sizes.control32 - theme.spacing.s6,
                     fill: selected ? c.sel : .clear, cornerRadius: theme.radii.sm) {
            HStack(spacing: theme.spacing.s6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: theme.sizes.icon14)).foregroundStyle(selected ? c.accent : c.tx3)
                }
                Text(label).font(theme.typography.meta.weight(selected ? .semibold : .regular)).foregroundStyle(selected ? c.accent : c.tx).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let count { Text("\(count)").font(theme.typography.mono).foregroundStyle(selected ? c.accent : c.tx3) }
            }
            .padding(.horizontal, theme.spacing.s6)
        }
    }
}

public struct ScopeGroupHeader: View {
    @Environment(\.appTheme) private var theme
    let title: String
    public init(title: String) { self.title = title }
    public var body: some View {
        Text(title.uppercased()).font(theme.typography.sidebarGroupLabel).foregroundStyle(theme.colors.tx2).lineLimit(1)
            .padding(.horizontal, theme.spacing.s6).frame(height: theme.sizes.control32 - theme.spacing.s6, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A project / repository / product row: colour dot or icon, name (+ path under it), count and a pin toggle.
public struct ScopeEntryRow: View {
    @Environment(\.appTheme) private var theme
    let name: String; var path: String?; var color: Color?; var systemImage: String?; var count: Int?
    var selected: Bool; var isPinned: Bool; var onPinToggle: (() -> Void)?; let onTap: () -> Void

    public init(name: String, path: String? = nil, color: Color? = nil, systemImage: String? = nil, count: Int? = nil,
                selected: Bool = false, isPinned: Bool = false, onPinToggle: (() -> Void)? = nil, onTap: @escaping () -> Void) {
        self.name = name; self.path = path; self.color = color; self.systemImage = systemImage; self.count = count
        self.selected = selected; self.isPinned = isPinned; self.onPinToggle = onPinToggle; self.onTap = onTap
    }

    public var body: some View {
        let c = theme.colors
        HoverSurface(onTap: onTap, selected: selected, height: path == nil ? theme.sizes.control32 - theme.spacing.s6 : nil,
                     fill: selected ? c.sel : .clear, cornerRadius: theme.radii.sm) {
            HStack(spacing: theme.spacing.s6) {
                if let color { Circle().fill(color).frame(width: theme.sizes.icon12 / 2, height: theme.sizes.icon12 / 2) }
                else { Image(systemName: systemImage ?? "folder").font(.system(size: theme.sizes.icon14)).foregroundStyle(selected ? c.accent : c.tx3) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(theme.typography.meta.weight(selected ? .semibold : .regular)).foregroundStyle(selected ? c.accent : c.tx).lineLimit(1)
                    if let path, !path.isEmpty {
                        Text(path.hasPrefix("/") ? path : "/ \(path)").font(theme.typography.caption).foregroundStyle(c.tx3).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let count { Text("\(count)").font(theme.typography.mono).foregroundStyle(selected ? c.accent : c.tx3) }
                if let onPinToggle {
                    SidebarPinButton(pinned: isPinned, tooltip: isPinned ? appString("unpinProject", "Unpin") : appString("pinProject", "Pin"), onTap: onPinToggle)
                }
            }
            .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s2)
        }
    }
}
