/// Ported from: lib/features/workspace_overview/presentation/widgets/my_work_meta.dart
import CoreUI
import SwiftUI

/// A quiet icon + text fact in a row's meta line (sprint, subtasks...).
struct MyWorkFact: View {
    @Environment(\.appTheme) private var theme
    let systemImage: String
    let text: String
    /// Overrides the muted tone, e.g. red for an overdue deadline.
    var color: Color?
    /// Caps long names (sprints) so the other facts stay on the line.
    var maxWidth: CGFloat?

    var body: some View {
        let tint = color ?? theme.colors.tx3
        HStack(spacing: theme.spacing.s4) {
            Image(systemName: systemImage).font(.system(size: theme.sizes.icon12)).foregroundStyle(tint)
            Text(text).font(theme.typography.caption).foregroundStyle(tint).lineLimit(1)
                .frame(maxWidth: maxWidth ?? .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: maxWidth == nil, vertical: false)
    }
}

/// "Due Oct 12", red once the day has passed.
struct MyWorkDueFact: View {
    @Environment(\.appTheme) private var theme
    let due: Date

    var body: some View {
        let overdue = due < Calendar.current.startOfDay(for: Date())
        MyWorkFact(systemImage: "calendar", text: OL.dashboardDue(monthDay(due)), color: overdue ? theme.colors.red : nil)
    }
}
