import CoreDomain
import SwiftUI

/// Ported from: lib/core/widgets/badges.dart (PriorityTag, WorkspaceTag, MiniTag, StatusDot, SkeletonBox) +
/// lib/shared/board/presentation/widgets/ticket_card_meta.dart (SeverityTag).
public struct PriorityTag: View {
    @Environment(\.appTheme) private var theme
    let provider: ProviderType, priority: Priority, large: Bool
    public init(_ provider: ProviderType, _ priority: Priority, large: Bool = false) {
        self.provider = provider; self.priority = priority; self.large = large
    }
    public var body: some View {
        let color = theme.colors.priorityColor(priority)
        Text(priorityLabel(provider, priority))
            .font(theme.typography.badge).foregroundStyle(color)
            .padding(.horizontal, large ? theme.spacing.s8 : theme.spacing.s6)
            .padding(.vertical, large ? theme.spacing.s4 : theme.spacing.s2)
            .background(color.opacity(0.17), in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay { if theme.showOutline { RoundedRectangle(cornerRadius: theme.radii.md).stroke(color.opacity(0.44), lineWidth: theme.borders.hairline) } }
    }
}

public struct SeverityTag: View {
    @Environment(\.appTheme) private var theme
    let severity: Int
    public init(_ severity: Int) { self.severity = severity }
    public var body: some View {
        let color = theme.colors.severityColor(severity) ?? theme.colors.tx3
        HStack(spacing: theme.spacing.s4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(zentaoSeverityLabel(severity) ?? "S\(severity)").font(theme.typography.badge).foregroundStyle(color)
        }
        .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s2)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay { if theme.showOutline { RoundedRectangle(cornerRadius: theme.radii.md).stroke(color.opacity(0.4), lineWidth: theme.borders.hairline) } }
    }
}

/// Workspace name with its colour dot.
public struct WorkspaceTag: View {
    @Environment(\.appTheme) private var theme
    let color: Color, label: String
    public init(_ color: Color, _ label: String) { self.color = color; self.label = label }
    public var body: some View {
        HStack(spacing: theme.spacing.s4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(theme.typography.mono.weight(.semibold)).foregroundStyle(color).lineLimit(1)
        }
        .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s2)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: theme.radii.sm))
        .overlay { if theme.showOutline { RoundedRectangle(cornerRadius: theme.radii.sm).stroke(color.opacity(0.3), lineWidth: theme.borders.hairline) } }
    }
}

public struct MiniTag: View {
    @Environment(\.appTheme) private var theme
    let label: String, color: Color
    public init(_ label: String, _ color: Color) { self.label = label; self.color = color }
    public var body: some View {
        Text(label).font(theme.typography.badge).foregroundStyle(color)
            .padding(.horizontal, theme.spacing.s4).padding(.vertical, theme.spacing.s2)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: theme.radii.xs))
            .overlay { if theme.showOutline { RoundedRectangle(cornerRadius: theme.radii.xs).stroke(color.opacity(0.4), lineWidth: theme.borders.hairline) } }
    }
}

/// Coloured dot for a unified status.
public struct StatusDot: View {
    @Environment(\.appTheme) private var theme
    let status: UnifiedStatus, size: CGFloat
    public init(_ status: UnifiedStatus, size: CGFloat = 8) { self.status = status; self.size = size }
    public var body: some View { Circle().fill(theme.colors.statusColor(status)).frame(width: size, height: size) }
}

/// Shimmering placeholder block.
public struct SkeletonBox: View {
    @Environment(\.appTheme) private var theme
    var width: CGFloat?; var height: CGFloat; var radius: CGFloat?
    @State private var phase: CGFloat = 0
    public init(width: CGFloat? = nil, height: CGFloat = 12, radius: CGFloat? = nil) {
        self.width = width; self.height = height; self.radius = radius
    }
    public var body: some View {
        let c = theme.colors
        RoundedRectangle(cornerRadius: radius ?? theme.radii.sm)
            .fill(LinearGradient(colors: [c.skel, c.skel2, c.skel], startPoint: UnitPoint(x: -1 + 2 * phase, y: 0),
                                 endPoint: UnitPoint(x: 2 * phase, y: 0)))
            .frame(width: width, height: height).frame(maxWidth: width == nil ? .infinity : nil)
            .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.5 } }
    }
}
