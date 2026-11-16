/// Ported from: lib/tools/zentao/presentation/widgets/{zentao_status_pill,zentao_priority_badge}.dart
import CoreDomain
import CoreUI
import SwiftUI

/// Semantic status pill for ZenTao work items (Doing, Done, Verify, Paused, Waiting).
public struct ZentaoStatusPill: View {
    @Environment(\.appTheme) private var theme
    let status: UnifiedStatus; let providerStatus: String
    public init(status: UnifiedStatus, providerStatus: String) { self.status = status; self.providerStatus = providerStatus }

    public var body: some View {
        let c = theme.colors
        let (label, color): (String, Color) = switch status {
        case .inprogress: ("Doing", c.accent)
        case .done: ("Done", c.green)
        case .review: ("Verify", c.accent)
        case .blocked: ("Paused", c.amber)
        default: (providerStatus.isEmpty ? "Waiting" : providerStatus, c.tx3)
        }
        Text(label).font(theme.typography.mono.weight(.semibold)).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: theme.radii.xs))
    }
}

/// Circular numbered indicator (1-4) for a ZenTao ticket's priority.
public struct ZentaoPriorityBadge: View {
    @Environment(\.appTheme) private var theme
    let priority: Priority; let size: CGFloat
    public init(_ priority: Priority, size: CGFloat = 20) { self.priority = priority; self.size = size }

    public var body: some View {
        let c = theme.colors
        let (symbol, color): (String, Color) = switch priority {
        case .urgent: ("①", c.red)
        case .high: ("②", c.amber)
        case .medium: ("③", c.accent)
        case .low: ("④", c.tx3)
        }
        Text(symbol).font(theme.typography.mono.weight(.bold)).foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: Circle())
            .overlay(Circle().stroke(color.opacity(0.35), lineWidth: theme.borders.hairline))
    }
}
