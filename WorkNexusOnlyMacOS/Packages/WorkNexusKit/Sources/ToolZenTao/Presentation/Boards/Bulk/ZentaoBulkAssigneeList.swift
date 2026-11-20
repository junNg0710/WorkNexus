/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// The people a bulk assign can go to, one row each: who they are, what they hold on the board (open, a red dot when
/// something is overdue), and how many of the picked tickets they are not on the team of. Click a row to pick them.
struct ZentaoBulkAssigneeList: View {
    @Environment(\.appTheme) private var theme
    let accountId: String; let people: [ZenTaoBulkAssignee]; let picked: String?; let ticketCount: Int
    let onPick: (String) -> Void

    /// Up to this tall - as tall as its rows when there are few - then it scrolls.
    private static let maxHeight: CGFloat = 280

    var body: some View {
        if people.isEmpty {
            AppInlineNote(appString("noMatchingUsers", "No matching users"))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(people) { p in
                        ZentaoBulkAssigneeRow(accountId: accountId, person: p, picked: picked == p.login, ticketCount: ticketCount) { onPick(p.login) }
                    }
                }
            }
            .frame(maxHeight: Self.maxHeight)
            .fixedSize(horizontal: false, vertical: true)
            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        }
    }
}

private struct ZentaoBulkAssigneeRow: View {
    @Environment(\.appTheme) private var theme
    let accountId: String; let person: ZenTaoBulkAssignee; let picked: Bool; let ticketCount: Int; let onTap: () -> Void

    var body: some View {
        let c = theme.colors
        let off = person.cannotTake >= ticketCount && ticketCount > 0
        HoverSurface(onTap: onTap, selected: picked, cornerRadius: theme.radii.sm) {
            HStack(spacing: theme.spacing.s8) {
                ZentaoPersonAvatar(accountId: accountId, name: person.name, diameter: theme.sizes.icon20)
                if person.pinned {
                    Image(systemName: "pin.fill").font(.system(size: theme.sizes.icon12 - 2)).foregroundStyle(c.accent).rotationEffect(.degrees(30))
                }
                Text(person.name).font(theme.typography.body).foregroundStyle(off ? c.tx3 : c.tx).lineLimit(1)
                Text(person.login).font(theme.typography.meta).foregroundStyle(c.tx3).lineLimit(1)
                Spacer(minLength: theme.spacing.s8)
                if person.cannotTake > 0 {
                    Text(appFormat("leaderBulkNotOnTeam", "%1$@ not on their team", "\(person.cannotTake)"))
                        .font(theme.typography.meta).foregroundStyle(c.amber).lineLimit(1)
                }
                if person.overdue > 0 {
                    Circle().fill(c.red).frame(width: theme.spacing.s6, height: theme.spacing.s6)
                        .help(appFormat("leaderOverdueCount", "%1$@ overdue", "\(person.overdue)"))
                }
                Text(appFormat("leaderOpenCount", "%1$@ open", "\(person.open)")).font(theme.typography.meta).foregroundStyle(c.tx2)
                    .monospacedDigit().lineLimit(1)
                Image(systemName: "checkmark").font(.system(size: theme.sizes.icon12, weight: .semibold)).foregroundStyle(c.accent)
                    .opacity(picked ? 1 : 0)
            }
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s6)
        }
        .help(off ? appString("tipBulkNotOnTeam", "Not on the team of any picked ticket: ZenTao would refuse it") : "")
    }
}
