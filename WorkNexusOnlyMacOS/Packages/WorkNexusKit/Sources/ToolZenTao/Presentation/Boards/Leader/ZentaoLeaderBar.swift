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
        // One row when the people, the one-click filters and the keyword fit side by side - the usual case, and a row of
        // the board's height won back; two rows (each scrolling sideways) for a big team or a narrow window.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: theme.spacing.s8) {
                ZentaoPeopleStrip(state: state, bugs: bugs, scrolls: false)
                ZentaoQuickChips(state: state, bugs: bugs, scrolls: false)
                Spacer(minLength: theme.spacing.s8)
                ZentaoLeaderTrailing(state: state, bugs: bugs, keyword: keyword)
            }
            VStack(alignment: .leading, spacing: theme.spacing.s6) {
                ZentaoPeopleStrip(state: state, bugs: bugs)
                HStack(spacing: theme.spacing.s8) {
                    ZentaoQuickChips(state: state, bugs: bugs)
                    Spacer(minLength: 0)
                    ZentaoLeaderTrailing(state: state, bugs: bugs, keyword: keyword)
                }
            }
        }
        .padding(.top, theme.spacing.s6)
    }
}

/// The end of the bar: how much is loaded, the help and the keyword field.
private struct ZentaoLeaderTrailing: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState; let bugs: Bool
    let keyword: Binding<String>

    var body: some View {
        HStack(spacing: theme.spacing.s8) {
            if state.team(bugs: bugs) != nil { ZentaoTeamStatus(state: state, bugs: bugs) } else { ZentaoLeaderCoverage(state: state, bugs: bugs) }
            ZentaoLeaderHelp(bugs: bugs)
            AppSearchField(text: keyword, hint: appString("leaderFilterHint", "Filter by id, title or person"),
                           height: theme.sizes.control32 - theme.spacing.s4)
                .frame(minWidth: 150, idealWidth: 220, maxWidth: 260)
                .help(appString("tipLeaderFilter", "Narrows the board as you type: by id, title or the person who holds it"))
        }
    }
}

/// A row of chips: scrolling sideways in a row of its own, or at its own width (with a divider after it when `divided`)
/// as part of a shared row.
struct LeaderChipRow<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let scrolls: Bool
    let divided: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if scrolls {
            ScrollView(.horizontal, showsIndicators: false) { content }
        } else {
            HStack(spacing: theme.spacing.s8) {
                content
                if divided { Rectangle().fill(theme.colors.line).frame(width: theme.borders.hairline, height: theme.sizes.icon16) }
            }
            .fixedSize()
        }
    }
}
