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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var width: CGFloat?; var height: CGFloat; var radius: CGFloat?
    public init(width: CGFloat? = nil, height: CGFloat = 12, radius: CGFloat? = nil) {
        self.width = width; self.height = height; self.radius = radius
    }
    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? theme.radii.sm)
        shape.fill(theme.colors.skel)
            .overlay { if !reduceMotion { SkeletonSheen().clipShape(shape) } }
            .frame(width: width, height: height).frame(maxWidth: width == nil ? .infinity : nil)
    }
}

/// The light that sweeps across loading placeholders. Every placeholder on screen reads the same clock and its own place
/// in the window, so one band of light crosses them all together, left to right, as on a native placeholder - not each
/// box flickering on its own.
struct SkeletonSheen: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.animationsRun) private var animationsRun
    /// One sweep, and how far it travels (wider than any window).
    static let period: TimeInterval = 1.6
    static let travel: CGFloat = 2600
    static let band: CGFloat = 320

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !animationsRun)) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
                let center = -Self.band + CGFloat(t) * Self.travel - frame.minX
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: theme.colors.skel2, location: 0.5),
                                       .init(color: .clear, location: 1)],
                               startPoint: UnitPoint(x: (center - Self.band / 2) / max(frame.width, 1), y: 0.5),
                               endPoint: UnitPoint(x: (center + Self.band / 2) / max(frame.width, 1), y: 0.5))
            }
        }
        .allowsHitTesting(false)
    }
}
