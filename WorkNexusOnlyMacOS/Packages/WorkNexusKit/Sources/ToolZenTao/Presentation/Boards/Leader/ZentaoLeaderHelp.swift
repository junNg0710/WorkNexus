/// Not in the Flutter app.
import CoreUI
import SwiftUI

/// A "?" at the end of the leader bar: pointing at it (or clicking it) opens a short note on how to use the tools above.
struct ZentaoLeaderHelp: View {
    @Environment(\.appTheme) private var theme
    let bugs: Bool
    @State private var open = false
    @State private var overIcon = false
    @State private var overNote = false

    /// The note's lines: an icon and the text. Tasks and Bugs share them; the hours line is about tasks only.
    private var lines: [(icon: String, text: String)] {
        var out: [(String, String)] = [
            ("person.2", appString("leaderHelpPeople", "People: click a name to see only their work; ⌘-click adds more people. The number is what they still have open, the red dot means something is overdue. \"Everyone\" clears the pick.")),
            ("line.3.horizontal.decrease", appString("leaderHelpChips", "Chips: one-click filters (overdue, due soon, unassigned, high priority…). The number is how many each would keep. Overdue and due-soon count by calendar day.")),
            ("magnifyingglass", appString("leaderHelpFilter", "Filter box: narrows the board as you type, by id, title or person. ⌘K searches every cached ticket of the account, and an id that isn't cached (#123) can be looked up on the server with Return.")),
            ("checkmark.circle", appString("leaderHelpSelect", "Pick tickets: ⌘-click a card or row, ⇧-click to pick a range. With some picked, a plain click picks too. Esc or Clear drops the pick.")),
            ("person.badge.plus", appString("leaderHelpBulk", "Act on the pick: Assign…, Priority… or Close… from the bar at the bottom. It says what will change and what is skipped first, then runs ticket by ticket; failed ones can be retried.")),
            ("cursorarrow.click.2", appString("leaderHelpMenu", "Right-click a ticket: Select, Assign… or Priority… without opening it.")),
            ("person.3", appString("leaderHelpTeam", "Team (header): follow a saved group of people across every execution or product instead of just one. Pick an execution again to leave it.")),
            ("arrow.down.circle", appString("leaderHelpLoad", "\"Load all\": counts and filters only cover what is loaded; this reads the rest of the open views.")),
        ]
        if !bugs { out.insert(("clock", appString("leaderHelpHours", "Cards show the hours left, and a tag for how late or how close the deadline is. Sort: deadline puts the most overdue first.")), at: 6) }
        return out
    }

    var body: some View {
        Image(systemName: "questionmark.circle").font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.tx3)
            .padding(theme.spacing.s4).contentShape(Rectangle())
            .onTapGesture { open.toggle() }
            .onHover { overIcon = $0; sync() }
            .accessibilityLabel(appString("leaderHelpTitle", "How to use the team tools"))
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: theme.spacing.s10) {
                    Text(appString("leaderHelpTitle", "How to use the team tools")).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: theme.spacing.s8) {
                            Image(systemName: line.icon).font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.accent)
                                .frame(width: theme.sizes.icon14 + theme.spacing.s4)
                            Text(line.text).font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(theme.spacing.s14).frame(width: 380, alignment: .leading)
                .onHover { overNote = $0; sync() }
            }
    }

    /// Open while the pointer is over the icon or the note; closes a moment after it leaves both (so it can reach the note).
    private func sync() {
        if overIcon || overNote { open = true; return }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            if !overIcon && !overNote { open = false }
        }
    }
}
