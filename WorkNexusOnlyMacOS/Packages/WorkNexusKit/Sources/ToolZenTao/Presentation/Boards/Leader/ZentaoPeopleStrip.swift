/// Not in the Flutter app.
import AppKit
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// One chip per person on the board with what they hold (open tickets, a red dot when something is overdue); click to
/// see only their work, ⌘-click to add or remove people. "Everyone" clears the pick.
struct ZentaoPeopleStrip: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState; let bugs: Bool

    var body: some View {
        let leader = state.leader(bugs: bugs)
        let narrowing = !leader.quick.isEmpty || !leader.trimmedKeyword.isEmpty
        // While chips or a keyword narrow the board, people with nothing left are noise: only the picked ones stay.
        let rows = state.workload(bugs: bugs).filter { !narrowing || $0.open > 0 || leader.people.contains($0.login) }
        let loading = (bugs ? state.bugSlice.isLoading : state.taskSlice.isLoading) || (state.team(bugs: bugs)?.isLoading ?? false)
        if loading && rows.count <= 1 && leader.people.isEmpty {
            // The row the people will fill, held while the board loads: the board below does not jump down when they come.
            HStack(spacing: theme.spacing.s6) {
                ForEach(0..<6, id: \.self) { i in SkeletonBox(width: [72, 132, 118, 150, 104, 126][i], height: theme.sizes.control32 - theme.spacing.s4, radius: theme.radii.pill) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if rows.count > 1 || !leader.people.isEmpty {
            let total = rows.reduce(0) { $0 + $1.open }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing.s6) {
                    PersonChipBody(name: appString("leaderEveryone", "Everyone"), count: total, overdue: 0, accountId: nil, login: "",
                                   active: leader.people.isEmpty,
                                   help: appString("tipEveryone", "Show everyone's tickets. The number is how many are still open")) {
                        state.updateLeader(bugs: bugs) { $0.people = [] }
                    }
                    ForEach(rows) { row in
                        PersonChipBody(name: row.isUnassigned ? appString("unassigned", "Unassigned") : (state.memberNames[row.login] ?? row.login),
                                       count: row.open, overdue: row.overdue, accountId: state.place.accountId, login: row.login,
                                       active: leader.people.contains(row.login), help: Self.help(row, bugs: bugs)) {
                            let add = NSEvent.modifierFlags.contains(.command)
                            state.updateLeader(bugs: bugs) { f in
                                if add { f = f.toggled(person: row.login) }
                                else { f.people = f.people == [row.login] ? [] : [row.login] }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func help(_ row: ZenTaoWorkload, bugs: Bool) -> String {
        var parts = [appFormat("leaderOpenCount", "%1$@ open", "\(row.open)")]
        if row.overdue > 0 { parts.append(appFormat("leaderOverdueCount", "%1$@ overdue", "\(row.overdue)")) }
        if row.dueSoon > 0 { parts.append(appFormat("leaderDueSoonCount", "%1$@ due soon", "\(row.dueSoon)")) }
        if !bugs, row.hoursLeft > 0 { parts.append(appFormat("taskHoursLeft", "%1$@ h left", zentaoHoursText(row.hoursLeft))) }
        return parts.joined(separator: " · ")
    }
}

private struct PersonChipBody: View {
    @Environment(\.appTheme) private var theme
    let name: String; let count: Int; let overdue: Int; let accountId: String?; let login: String
    let active: Bool; let help: String?; let onTap: () -> Void

    var body: some View {
        let c = theme.colors
        let height = theme.sizes.control32 - theme.spacing.s4
        HoverSurface(onTap: onTap, selected: active, height: height, fill: active ? c.sel : c.panel2,
                     border: active ? c.accent : (theme.showOutline ? c.line : nil), cornerRadius: height / 2) {
            HStack(spacing: theme.spacing.s6) {
                if let accountId, !login.isEmpty { ZentaoPersonAvatar(accountId: accountId, name: name, diameter: 18) }
                else if login.isEmpty, accountId != nil { Image(systemName: "person.fill.questionmark").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.tx3) }
                Text(name).font(theme.typography.metaStrong).foregroundStyle(active ? c.tx : c.tx2).lineLimit(1)
                Text("\(count)").font(theme.typography.meta).foregroundStyle(c.tx3)
                if overdue > 0 { Circle().fill(c.red).frame(width: theme.spacing.s6, height: theme.spacing.s6) }
            }
            .padding(.horizontal, theme.spacing.s10)
        }
        .fixedSize()
        .help(help ?? "")
    }
}
