/// Ported from: lib/features/workspace_overview/presentation/widgets/dashboard_activity_list.dart
import CoreDomain
import CoreUI
import SwiftUI

/// Recent activity as a timeline - the object's kind icon on one thin line: who did what to which object, its title,
/// and when. Activity on a bug, task or story opens it in the detail panel.
struct DashboardActivityList: View {
    let model: OverviewModel
    let account: Account
    let activities: [ZenTaoDashboardActivity]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(activities.enumerated()), id: \.element.id) { i, a in
                DashboardActivityRow(model: model, account: account, activity: a, last: i == activities.count - 1)
            }
        }
    }
}

private struct DashboardActivityRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let model: OverviewModel
    let account: Account
    let activity: ZenTaoDashboardActivity
    /// The last event ends the timeline's line.
    let last: Bool

    var body: some View {
        let kind = DashboardItemKind.fromObjectType(activity.objectType)
        let opens = kind?.isTicket == true && !activity.objectId.isEmpty
        HoverSurface(onTap: opens ? open : nil) {
            HStack(alignment: .top, spacing: theme.spacing.s12) {
                VStack(spacing: 0) {
                    ZenTaoKindIcon(activity.objectType)
                    if !last {
                        Rectangle().fill(theme.colors.line).frame(width: theme.borders.hairline)
                            .frame(maxHeight: .infinity).padding(.vertical, theme.spacing.s4)
                    }
                }
                ActivityText(activity: activity).padding(.bottom, theme.spacing.s14).padding(.trailing, theme.spacing.s4)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func open() {
        guard let kind = DashboardItemKind.fromObjectType(activity.objectType) else { return }
        Task { await model.open(account, kind: kind, id: activity.objectId, toasts: toasts) }
    }
}

/// "actor action Bug #12" over the object's title, with when it happened at the right.
private struct ActivityText: View {
    @Environment(\.appTheme) private var theme
    let activity: ZenTaoDashboardActivity

    var body: some View {
        let c = theme.colors, t = theme.typography
        let ref = ticketRef(.zentao, activity.objectId, capitalized(activity.objectType))
        VStack(alignment: .leading, spacing: theme.spacing.s2) {
            HStack(alignment: .top, spacing: theme.spacing.s8) {
                (Text(activity.actor).font(t.label).foregroundStyle(c.tx)
                    + Text(" \(activity.action) ").font(t.meta).foregroundStyle(c.tx2)
                    + Text(ref).font(t.mono).foregroundStyle(c.tx3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(shortWhen(activity.date)).font(t.caption).foregroundStyle(c.tx3)
            }
            if let name = activity.objectName, !name.isEmpty {
                Text(name).font(t.meta).foregroundStyle(c.tx).lineLimit(2)
            }
        }
    }

    private func capitalized(_ s: String) -> String { s.isEmpty ? s : s.prefix(1).uppercased() + s.dropFirst() }
}
