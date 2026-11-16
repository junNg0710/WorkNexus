/// Ported from: lib/tools/zentao/presentation/detail/{bug_status_strip,task_effort_bar}.dart
import CoreDomain
import CoreUI
import SwiftUI

/// A ZenTao bug's status pill, in the sidebar's Status row: its raw status, with the resolution folded in once
/// resolved ("Resolved · Fixed").
public struct ZentaoBugStatusStrip: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket; let bug: ZenTaoBugEntity
    public init(ticket: Ticket, bug: ZenTaoBugEntity) { self.ticket = ticket; self.bug = bug }

    /// "Resolved · Fixed"; nil for a ticket without a status.
    public static func label(ticket: Ticket, bug: ZenTaoBugEntity) -> String? {
        let raw = ticket.providerStatus.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { return nil }
        // The resolution is how the bug was resolved, so it reads as part of the status rather than as a chip of its own.
        let resolution = raw.lowercased() == "active" ? nil : zentaoResolutionLabel(bug.resolution)
        return [raw.prefix(1).uppercased() + raw.dropFirst(), resolution].compactMap { $0 }.joined(separator: " · ")
    }

    private var icon: String {
        switch ticket.providerStatus.trimmingCharacters(in: .whitespaces).lowercased() {
        case "active": "exclamationmark.circle"
        case "resolved": "checkmark.circle"
        case "closed": "xmark.circle"
        default: "circle"
        }
    }

    public var body: some View {
        if let label = Self.label(ticket: ticket, bug: bug) {
            let tint = theme.colors.statusColor(ticket.status)
            HStack(spacing: theme.spacing.s4) {
                Image(systemName: icon).font(.system(size: theme.sizes.icon12))
                Text(label).font(theme.typography.badge)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s2)
            .background(tint.opacity(0.14), in: Capsule())
        }
    }
}

/// A ZenTao task's hours as a progress bar (logged against left, the estimate under it), opening the task's body.
/// Renders nothing for a task with no hours on record.
public struct ZentaoTaskEffortBar: View {
    @Environment(\.appTheme) private var theme
    let task: ZenTaoTaskEntity
    public init(task: ZenTaoTaskEntity) { self.task = task }

    public var body: some View {
        if let effort = SummarizeTaskEffort()(task) {
            let c = theme.colors
            VStack(alignment: .leading, spacing: theme.spacing.s6) {
                HStack {
                    Text(zentaoHoursLoggedText(effort.consumed)).font(theme.typography.bodyStrong).foregroundStyle(c.tx)
                    Spacer(minLength: 0)
                    Text(appFormat("taskHoursLeft", "%1$@ h left", zentaoHoursText(effort.left))).font(theme.typography.meta).foregroundStyle(c.tx2)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(c.panel2)
                        Capsule().fill(c.accent).frame(width: geo.size.width * effort.progress)
                    }
                }
                .frame(height: theme.spacing.s6)
                if effort.estimate > 0 {
                    Text(appFormat("taskEstimateHours", "Estimate %1$@ h", zentaoHoursText(effort.estimate))).font(theme.typography.caption).foregroundStyle(c.tx3)
                }
            }
        }
    }
}
