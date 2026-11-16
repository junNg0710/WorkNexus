/// Ported from: lib/features/workspace_overview/presentation/widgets/dashboard_execution_list.dart
import CoreDomain
import CoreUI
import SwiftUI

/// The user's unfinished executions (sprints): name, project and status over a progress bar, then when it ends and
/// how many days are left.
struct DashboardExecutionList: View {
    @Environment(\.appTheme) private var theme
    let executions: [ZenTaoDashboardExecution]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s20) {
            ForEach(executions) { DashboardExecutionRow(execution: $0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardExecutionRow: View {
    @Environment(\.appTheme) private var theme
    let execution: ZenTaoDashboardExecution

    var body: some View {
        let c = theme.colors, t = theme.typography
        let e = execution
        let percent = e.progress
        let value = min(max((percent ?? 0) / 100, 0), 1)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.spacing.s8) {
                Text(e.name).font(t.bodyStrong).foregroundStyle(c.tx).lineLimit(1)
                Spacer(minLength: 0)
                if let status = e.status {
                    TintedPill(zentaoStatusWord(status, execution: true), tint: dashboardStatusColor(c, status))
                }
            }
            // The project only adds information when named differently.
            if let project = e.projectName, project != e.name {
                Text(project).font(t.caption).foregroundStyle(c.tx3).lineLimit(1).padding(.top, theme.spacing.s2)
            }
            HStack(spacing: theme.spacing.s8) {
                ExecutionProgressBar(value: value)
                if let percent {
                    Text("\(Int(percent.rounded()))%").font(t.label).monospacedDigit().foregroundStyle(c.tx2)
                        .frame(minWidth: OverviewLayout.percentColumn, alignment: .trailing)
                }
            }
            .padding(.top, theme.spacing.s8)
            if let end = e.end { ExecutionEndLine(end: end).padding(.top, theme.spacing.s6) }
        }
    }
}

/// A thin rounded track filled to `value`, green once complete.
private struct ExecutionProgressBar: View {
    @Environment(\.appTheme) private var theme
    let value: Double

    var body: some View {
        Capsule().fill(theme.colors.panel2)
            .frame(height: OverviewLayout.progressHeight)
            .overlay(alignment: .leading) {
                GeometryReader { box in
                    Capsule().fill(value >= 1 ? theme.colors.green : theme.colors.accent)
                        .frame(width: box.size.width * value)
                }
            }
    }
}

/// "Ends Oct 20 · 11 days left", the countdown red once past the end.
private struct ExecutionEndLine: View {
    @Environment(\.appTheme) private var theme
    let end: Date

    var body: some View {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: end)).day ?? 0
        let overdue = days < 0
        HStack {
            MyWorkFact(systemImage: "flag", text: OL.dashboardEnds(monthDay(end)))
            Spacer(minLength: 0)
            Text(overdue ? OL.dashboardDaysOverdue(-days) : OL.dashboardDaysLeft(days))
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(overdue ? theme.colors.red : days <= 3 ? theme.colors.amber : theme.colors.tx2)
        }
    }
}
