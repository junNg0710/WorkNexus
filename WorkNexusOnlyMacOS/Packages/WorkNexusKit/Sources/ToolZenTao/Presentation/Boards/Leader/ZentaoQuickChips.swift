/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// The leader's one-click filters, each with how many tickets it would keep. A chip that would keep nothing hides
/// unless it is on.
struct ZentaoQuickChips: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState; let bugs: Bool
    /// False lays the chips out at their own width, for the row shared with the people (`ZentaoLeaderBar`).
    var scrolls = true

    /// Which chips make sense on the board: bugs have no estimate and rarely a deadline to plan the week by.
    private var chips: [ZenTaoQuickFilter] {
        bugs ? [.overdue, .dueSoon, .unassigned, .highPriority, .stale]
             : [.overdue, .dueSoon, .dueThisWeek, .unassigned, .highPriority, .stale, .noDeadline, .noEstimate]
    }

    static func label(_ chip: ZenTaoQuickFilter) -> String {
        switch chip {
        case .overdue: appString("leaderOverdue", "Overdue")
        case .dueSoon: appFormat("leaderDueSoon", "Due in %1$@ days", "\(ZenTaoLeaderFilter.soonDays)")
        case .dueThisWeek: appString("dueThisWeek", "Due this week")
        case .noDeadline: appString("leaderNoDeadline", "No deadline")
        case .unassigned: appString("unassigned", "Unassigned")
        case .highPriority: appString("leaderHighPriority", "High priority")
        case .stale: appFormat("leaderStale", "Idle %1$@ days+", "\(ZenTaoLeaderFilter.staleDays)")
        case .noEstimate: appString("leaderNoEstimate", "No estimate")
        }
    }

    /// What the chip keeps, for its tooltip.
    static func help(_ chip: ZenTaoQuickFilter) -> String {
        switch chip {
        case .overdue: appString("tipChipOverdue", "Open tickets whose deadline day has passed")
        case .dueSoon: appFormat("tipChipDueSoon", "Open tickets due today or within the next %1$@ days", "\(ZenTaoLeaderFilter.soonDays)")
        case .dueThisWeek: appString("tipChipWeek", "Open tickets due this week, Monday to Sunday")
        case .noDeadline: appString("tipChipNoDeadline", "Open tickets with no deadline set")
        case .unassigned: appString("tipChipUnassigned", "Open tickets nobody holds")
        case .highPriority: appString("tipChipHigh", "Open tickets of priority 1 or 2")
        case .stale: appFormat("tipChipStale", "Open tickets not updated for %1$@ days or more", "\(ZenTaoLeaderFilter.staleDays)")
        case .noEstimate: appString("tipChipNoEstimate", "Tasks with no estimate in hours")
        }
    }

    private func dot(_ chip: ZenTaoQuickFilter) -> Color? {
        switch chip {
        case .overdue: theme.colors.red
        case .dueSoon: theme.colors.amber
        default: nil
        }
    }

    var body: some View {
        let leader = state.leader(bugs: bugs)
        let counts = state.quickCounts(bugs: bugs)
        LeaderChipRow(scrolls: scrolls, divided: false) {
            HStack(spacing: theme.spacing.s6) {
                ForEach(chips.filter { (counts[$0] ?? 0) > 0 || leader.quick.contains($0) }, id: \.self) { chip in
                    FilterOptionChip(FilterChipOption(label: Self.label(chip), active: leader.quick.contains(chip),
                                                      onTap: { state.updateLeader(bugs: bugs) { $0 = $0.toggled(chip) } },
                                                      dotColor: dot(chip), count: counts[chip] ?? 0,
                                                      help: Self.help(chip) + " " + appString("tipChipSuffix", "The number is how many it would keep; click again to turn it off.")))
                }
                if leader.isActive {
                    AppButton(appString("clearAllFilters", "Clear all filters"), kind: .ghost) {
                        state.setLeader(ZenTaoLeaderFilter(), bugs: bugs)
                    }
                    .help(appString("tipClearLeader", "Turn off the picked people, the chips and the typed filter"))
                }
            }
        }
    }
}
