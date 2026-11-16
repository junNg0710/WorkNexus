/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SwiftUI

/// "120 of 340 loaded" with a button to load the rest, so the counts and filters above cover all of the work and not
/// only the first pages. Nothing once everything is in.
struct ZentaoLeaderCoverage: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState; let bugs: Bool

    var body: some View {
        let cover = state.leaderCoverage(bugs: bugs)
        let loading = state.loadingEverything.contains(bugs ? "bugs" : "tasks")
        if cover.more || loading {
            HStack(spacing: theme.spacing.s6) {
                if loading { ProgressView().controlSize(.small) }
                Text(appFormat("leaderLoadedOf", "%1$@ of %2$@ loaded", "\(cover.loaded)", "\(cover.total)"))
                    .font(theme.typography.meta).foregroundStyle(theme.colors.tx3).lineLimit(1)
                if !loading {
                    AppButton(appString("leaderLoadAll", "Load all"), kind: .ghost) { state.loadEverything(bugs: bugs) }
                        .help(appString("tipLoadAll", "Read the rest of the open views, so the counts and filters cover every ticket and not only the first pages"))
                }
            }
            .fixedSize()
        }
    }
}
