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

/// Who the tickets go to: the person picked, in a box of their own with a way to change them; until then (or while
/// changing), the search over the list of people. Picking someone clears the search, so they stay in view.
struct ZentaoBulkAssigneePicker: View {
    @Environment(\.appTheme) private var theme
    let accountId: String; let people: [ZenTaoBulkAssignee]; let ticketCount: Int
    @Binding var picked: String?; @Binding var filter: String
    @State private var changing = false

    private var shown: [ZenTaoBulkAssignee] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? people : people.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.login.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        let chosen = picked.flatMap { login in people.first { $0.login == login } }
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            if let chosen, !changing {
                ZentaoBulkPickedPerson(accountId: accountId, person: chosen, ticketCount: ticketCount) { changing = true }
            } else {
                AppSearchField(text: $filter, hint: appString("searchUsers", "Search users…"), autofocus: changing)
                ZentaoBulkAssigneeList(accountId: accountId, people: shown, picked: picked, ticketCount: ticketCount) { login in
                    picked = login; filter = ""; changing = false
                }
            }
        }
    }
}

/// The person picked, with their load, on an accent card; "Change" opens the search again.
private struct ZentaoBulkPickedPerson: View {
    @Environment(\.appTheme) private var theme
    let accountId: String; let person: ZenTaoBulkAssignee; let ticketCount: Int; let onChange: () -> Void

    var body: some View {
        let c = theme.colors
        HStack(spacing: theme.spacing.s10) {
            ZentaoPersonAvatar(accountId: accountId, name: person.name, diameter: theme.sizes.control32)
            VStack(alignment: .leading, spacing: theme.spacing.s2) {
                Text(person.name).font(theme.typography.bodyStrong).foregroundStyle(c.tx).lineLimit(1)
                HStack(spacing: theme.spacing.s6) {
                    Text(verbatim: person.login)
                    Text(verbatim: "·")
                    Text(appFormat("leaderOpenCount", "%1$@ open", "\(person.open)"))
                    if person.overdue > 0 {
                        Text(appFormat("leaderOverdueCount", "%1$@ overdue", "\(person.overdue)")).foregroundStyle(c.red)
                    }
                    if person.cannotTake > 0 {
                        Text(appFormat("leaderBulkNotOnTeam", "%1$@ not on their team", "\(person.cannotTake)")).foregroundStyle(c.amber)
                    }
                }
                .font(theme.typography.meta).foregroundStyle(c.tx2).lineLimit(1)
            }
            Spacer(minLength: theme.spacing.s8)
            AppButton(appString("leaderBulkChangePerson", "Change"), systemImage: "arrow.left.arrow.right", kind: .ghost, action: onChange)
        }
        .padding(theme.spacing.s10)
        .background(c.sel, in: RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(c.accent, lineWidth: theme.borders.hairline))
    }
}
