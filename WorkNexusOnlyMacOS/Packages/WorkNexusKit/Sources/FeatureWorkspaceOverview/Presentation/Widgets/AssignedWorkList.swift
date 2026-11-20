/// Ported from: lib/features/workspace_overview/presentation/widgets/assigned_work_list.dart
import CoreDomain
import CoreUI
import SwiftUI

/// The "Assigned to you (from all tools)" section on the Workspace Overview. Shows open items sorted by urgency,
/// capped at 20 with a "Show all {n}" toggle.
struct AssignedWorkList: View {
    @Environment(\.appTheme) private var theme
    @State private var expanded = false
    let model: OverviewModel
    /// The items to list; the model's assigned work when nil.
    var items: [AssignedWorkItem]?

    var body: some View {
        let all = items ?? model.assignedWork
        let overflow = all.count > OverviewLayout.assignedCap
        let shown = expanded || !overflow ? all : Array(all.prefix(OverviewLayout.assignedCap))
        CardSurface(fill: \.panel) {
            VStack(spacing: 0) {
                AssignedWorkHeader(count: all.count)
                Divider().overlay(theme.colors.line)
                if all.isEmpty {
                    Text(OL.noAssignedWork).font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
                        .frame(maxWidth: .infinity).padding(.horizontal, theme.spacing.s16).padding(.vertical, theme.spacing.s24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
                            if i > 0 { Divider().overlay(theme.colors.line) }
                            AssignedWorkRow(model: model, item: item)
                        }
                    }
                    .padding(theme.spacing.s6)
                    if overflow {
                        Divider().overlay(theme.colors.line)
                        AppButton(expanded ? OL.viewList : OL.showAllWithCount(all.count), kind: .ghost) { expanded.toggle() }
                            .padding(theme.spacing.s8)
                    }
                }
            }
        }
    }
}

private struct AssignedWorkHeader: View {
    @Environment(\.appTheme) private var theme
    let count: Int

    var body: some View {
        let c = theme.colors, t = theme.typography
        HStack(spacing: theme.spacing.s6) {
            // The hint gives way first when the header is narrow.
            Text(OL.assignedToYou).font(t.bodyStrong).foregroundStyle(c.tx).lineLimit(1).layoutPriority(1)
            Text(OL.fromAllTools).font(t.caption).foregroundStyle(c.tx3).lineLimit(1)
            Spacer(minLength: theme.spacing.s6)
            Text(verbatim: "\(count)").font(t.caption.weight(.semibold)).foregroundStyle(c.tx2)
                .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s2)
                .background(c.panel2, in: Capsule())
        }
        .padding(.horizontal, theme.spacing.s16).padding(.vertical, theme.spacing.s12)
    }
}
