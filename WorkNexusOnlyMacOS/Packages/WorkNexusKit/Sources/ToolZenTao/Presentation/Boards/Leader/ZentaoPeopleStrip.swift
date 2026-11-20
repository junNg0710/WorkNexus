/// Not in the Flutter app.
import AppKit
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// One chip per person on the board with what they hold (open tickets, a red dot when something is overdue); click to
/// see only their work, ⌘-click to add or remove people. "Everyone" clears the pick.
///
/// The chips wrap onto more rows instead of running off the side (the last one used to be cut, with nothing saying the
/// row scrolled). A big team shows its first `collapsedCount` people and "+N more", so the board keeps its height.
struct ZentaoPeopleStrip: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState; let bugs: Bool
    /// False lays the chips out at their own width, with a divider after them: one part of a row shared with the
    /// one-click filters (`ZentaoLeaderBar`), which is used only when everything fits.
    var scrolls = true
    /// Everyone is listed, not only the first `collapsedCount`.
    @State private var expanded = false

    /// How many people a big team shows before "+N more": about two rows of chips.
    static let collapsedCount = 12

    /// The people shown while collapsed: the first `limit`, and whoever is picked beyond them (a pick must stay in sight).
    static func collapsed(_ rows: [ZenTaoWorkload], picked: Set<String>, limit: Int = collapsedCount) -> [ZenTaoWorkload] {
        guard rows.count > limit + 1 else { return rows }
        return Array(rows.prefix(limit)) + rows.dropFirst(limit).filter { picked.contains($0.login) }
    }

    var body: some View {
        let leader = state.leader(bugs: bugs)
        let narrowing = !leader.quick.isEmpty || !leader.trimmedKeyword.isEmpty
        // While chips or a keyword narrow the board, people with nothing left are noise: only the picked ones stay.
        let pinned = state.pinnedPeople
        // The pinned people lead, in the leader's order; then everyone else, most work first.
        let rows = OrderWorkload()(state.workload(bugs: bugs).filter { !narrowing || $0.open > 0 || leader.people.contains($0.login) },
                                   pinned: pinned)
        let loading = (bugs ? state.bugSlice.isLoading : state.taskSlice.isLoading) || (state.team(bugs: bugs)?.isLoading ?? false)
        if loading && rows.count <= 1 && leader.people.isEmpty {
            // The row the people will fill, held while the board loads: the board below does not jump down when they come.
            HStack(spacing: theme.spacing.s6) {
                ForEach(0..<6, id: \.self) { i in SkeletonBox(width: [72, 132, 118, 150, 104, 126][i], height: theme.sizes.control32 - theme.spacing.s4, radius: theme.radii.pill) }
            }
            .frame(maxWidth: scrolls ? .infinity : nil, alignment: .leading)
        } else if rows.count > 1 || !leader.people.isEmpty {
            let total = rows.reduce(0) { $0 + $1.open }
            let shown = expanded ? rows : Self.collapsed(rows, picked: Set(leader.people))
            LeaderChipRow(wraps: scrolls, divided: true) {
                PersonChipBody(name: appString("leaderEveryone", "Everyone"), count: total, overdue: 0, accountId: nil, login: "",
                               active: leader.people.isEmpty,
                               help: appString("tipEveryone", "Show everyone's tickets. The number is how many are still open")) {
                    state.updateLeader(bugs: bugs) { $0.people = [] }
                }
                ForEach(shown) { row in
                    PersonChipBody(name: row.isUnassigned ? appString("unassigned", "Unassigned") : (state.memberNames[row.login] ?? row.login),
                                   count: row.open, overdue: row.overdue, accountId: state.place.accountId, login: row.login,
                                   active: leader.people.contains(row.login), pinned: pinned.contains(row.login),
                                   help: Self.help(row, bugs: bugs)) {
                        let add = NSEvent.modifierFlags.contains(.command)
                        state.updateLeader(bugs: bugs) { f in
                            if add { f = f.toggled(person: row.login) }
                            else { f.people = f.people == [row.login] ? [] : [row.login] }
                        }
                    }
                    .modifier(PersonChipArranging(state: state, login: row.login, pinned: pinned.contains(row.login), bugs: bugs))
                }
                if shown.count < rows.count {
                    MorePeopleChip(label: appFormat("leaderMorePeople", "+%1$@ more", "\(rows.count - shown.count)"),
                                   help: appString("tipMorePeople", "Show everyone on the board")) { expanded = true }
                } else if expanded, rows.count > Self.collapsedCount + 1 {
                    MorePeopleChip(label: appString("leaderFewerPeople", "Show fewer"), help: nil) { expanded = false }
                }
            }
        }
    }

    private static func help(_ row: ZenTaoWorkload, bugs: Bool) -> String {
        var parts = [appFormat("leaderOpenCount", "%1$@ open", "\(row.open)")]
        if row.overdue > 0 { parts.append(appFormat("leaderOverdueCount", "%1$@ overdue", "\(row.overdue)")) }
        if row.dueSoon > 0 { parts.append(appFormat("leaderDueSoonCount", "%1$@ due soon", "\(row.dueSoon)")) }
        if !bugs, row.hoursLeft > 0 { parts.append(appFormat("taskHoursLeft", "%1$@ h left", zentaoHoursText(row.hoursLeft))) }
        if !row.isUnassigned { parts.append(appString("tipPersonArrange", "Drag onto another person to move them; right-click to pin")) }
        return parts.joined(separator: " · ")
    }
}

/// "+8 more" / "Show fewer" at the end of a big team's chips.
private struct MorePeopleChip: View {
    @Environment(\.appTheme) private var theme
    let label: String; let help: String?; let onTap: () -> Void

    var body: some View {
        let height = theme.sizes.control32 - theme.spacing.s4
        HoverSurface(onTap: onTap, height: height, cornerRadius: height / 2) {
            Text(label).font(theme.typography.metaStrong).foregroundStyle(theme.colors.accent).lineLimit(1)
                .padding(.horizontal, theme.spacing.s10)
        }
        .fixedSize()
        .help(help ?? "")
    }
}

private struct PersonChipBody: View {
    @Environment(\.appTheme) private var theme
    let name: String; let count: Int; let overdue: Int; let accountId: String?; let login: String
    let active: Bool; var pinned = false; let help: String?; let onTap: () -> Void

    var body: some View {
        let c = theme.colors
        let height = theme.sizes.control32 - theme.spacing.s4
        HoverSurface(onTap: onTap, selected: active, height: height, fill: active ? c.sel : c.panel2,
                     border: active ? c.accent : (theme.showOutline ? c.line : nil), cornerRadius: height / 2) {
            HStack(spacing: theme.spacing.s6) {
                if let accountId, !login.isEmpty { ZentaoPersonAvatar(accountId: accountId, name: name, diameter: 18) }
                else if login.isEmpty, accountId != nil { Image(systemName: "person.fill.questionmark").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.tx3) }
                if pinned { Image(systemName: "pin.fill").font(.system(size: theme.sizes.icon12 - 2)).foregroundStyle(c.accent).rotationEffect(.degrees(30)) }
                Text(name).font(theme.typography.metaStrong).foregroundStyle(active ? c.tx : c.tx2).lineLimit(1)
                Text(verbatim: "\(count)").font(theme.typography.meta).foregroundStyle(c.tx3)
                if overdue > 0 { Circle().fill(c.red).frame(width: theme.spacing.s6, height: theme.spacing.s6) }
            }
            .padding(.horizontal, theme.spacing.s10)
        }
        .fixedSize()
        .help(help ?? "")
    }
}

/// A person's chip can be pinned to the front (right-click) and dragged onto another to move it there. "Unassigned" and
/// "Everyone" stay where they are. Cards dropped on a chip are assigned to that person (the whole pick when the card is
/// part of it).
private struct PersonChipArranging: ViewModifier {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState; let login: String; let pinned: Bool; let bugs: Bool
    @State private var over = false
    static let prefix = "zentao-person:"

    func body(content: Content) -> some View {
        if login.isEmpty {
            content
        } else {
            content
                .contextMenu {
                    Button { state.togglePinned(login) } label: {
                        Label(pinned ? appString("leaderUnpinPerson", "Unpin") : appString("leaderPinPerson", "Pin to the front"),
                              systemImage: pinned ? "pin.slash" : "pin")
                    }
                }
                .onDrag {
                    let payload = Self.prefix + login
                    DispatchQueue.main.async { state.draggingTickets = false }
                    return NSItemProvider(object: payload as NSString)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let item = items.first else { return false }
                    guard item.hasPrefix(Self.prefix) else { return assign(item) }
                    let moved = String(item.dropFirst(Self.prefix.count))
                    guard moved != login else { return false }
                    withAnimation(.easeOut(duration: theme.motion.fast)) { state.movePerson(moved, before: login) }
                    return true
                } isTargeted: { over = $0 }
                .overlay {
                    // Cards over a person: they go to them.
                    if over && state.draggingTickets {
                        Capsule().stroke(theme.colors.accent, lineWidth: theme.borders.thick)
                    }
                }
                .overlay(alignment: .leading) {
                    // Where the dragged person will land: just before this one.
                    if over && !state.draggingTickets {
                        Capsule().fill(theme.colors.accent).frame(width: theme.borders.thick * 2)
                            .padding(.vertical, theme.spacing.s2).offset(x: -theme.spacing.s4)
                    }
                }
        }
    }

    /// A card dropped here: it, or the pick it belongs to, goes to this person (the board's bulk bar runs it).
    private func assign(_ ticketId: String) -> Bool {
        state.draggingTickets = false
        let board = bugs ? state.bugBoard : state.taskBoard
        guard board.scoped.contains(where: { $0.id == ticketId }) else { return false }
        state.bulkDrop = ZentaoBulkDrop(bugs: bugs, login: login, ids: DroppedTicketIds()(dropped: ticketId, picked: board.selectedIds))
        return true
    }
}
