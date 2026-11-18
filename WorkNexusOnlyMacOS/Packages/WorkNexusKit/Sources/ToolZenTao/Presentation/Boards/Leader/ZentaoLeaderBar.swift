/// Not in the Flutter app: the team leader's strip under a ZenTao board's toolbar.
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Whose work is on the board (the people strip), the one-click filters, a keyword and how much of the board is loaded
/// (the order of the cards is the toolbar's Sort button). Shown on the Tasks and the Bugs boards alike.
struct ZentaoLeaderBar: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState; let bugs: Bool

    private var keyword: Binding<String> {
        Binding(get: { state.leader(bugs: bugs).keyword },
                set: { text in state.updateLeader(bugs: bugs) { $0.keyword = text } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s6) {
            ZentaoPeopleStrip(state: state, bugs: bugs)
            HStack(spacing: theme.spacing.s8) {
                ZentaoQuickChips(state: state, bugs: bugs)
                Spacer(minLength: 0)
                if state.team(bugs: bugs) != nil { ZentaoTeamStatus(state: state, bugs: bugs) } else { ZentaoLeaderCoverage(state: state, bugs: bugs) }
                ZentaoLeaderHelp(bugs: bugs)
                AppSearchField(text: keyword, hint: appString("leaderFilterHint", "Filter by id, title or person"),
                               height: theme.sizes.control32 - theme.spacing.s4)
                    .frame(minWidth: 150, idealWidth: 220, maxWidth: 260)
                    .help(appString("tipLeaderFilter", "Narrows the board as you type: by id, title or the person who holds it"))
            }
        }
        .padding(.top, theme.spacing.s6)
    }
}
