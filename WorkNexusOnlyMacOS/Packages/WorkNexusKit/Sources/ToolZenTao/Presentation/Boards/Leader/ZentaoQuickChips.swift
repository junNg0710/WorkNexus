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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.s6) {
                ForEach(chips.filter { (counts[$0] ?? 0) > 0 || leader.quick.contains($0) }, id: \.self) { chip in
                    FilterOptionChip(FilterChipOption(label: Self.label(chip), active: leader.quick.contains(chip),
                                                      onTap: { state.updateLeader(bugs: bugs) { $0 = $0.toggled(chip) } },
                                                      dotColor: dot(chip), count: counts[chip] ?? 0))
                }
                if leader.isActive {
                    AppButton(appString("clearAllFilters", "Clear all filters"), kind: .ghost) {
                        state.setLeader(ZenTaoLeaderFilter(), bugs: bugs)
                    }
                }
            }
        }
    }
}
