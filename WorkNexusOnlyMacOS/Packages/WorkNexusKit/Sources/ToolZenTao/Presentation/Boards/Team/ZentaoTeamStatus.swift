/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SwiftUI

/// What was read of the team's people: progress while it goes, and who could not be read, with a retry.
struct ZentaoTeamStatus: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState; let bugs: Bool

    var body: some View {
        if let team = state.team(bugs: bugs) {
            let failed = team.failed
            HStack(spacing: theme.spacing.s6) {
                if team.isLoading {
                    ProgressView().controlSize(.small)
                    let done = team.logins.filter { !(team.loads[$0]?.isLoading ?? true) }.count
                    Text(appFormat("leaderTeamReading", "Reading %1$@ of %2$@ people", "\(done)", "\(team.logins.count)"))
                        .font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
                }
                if !failed.isEmpty && !team.isLoading {
                    Text(appFormat("leaderTeamFailed", "Couldn't read %1$@ people", "\(failed.count)"))
                        .font(theme.typography.meta).foregroundStyle(theme.colors.red)
                        .help(failed.map { login in
                            let reason: String = { if case .failed(let m)? = team.loads[login] { return m } else { return "" } }()
                            return "\(login): \(reason)"
                        }.joined(separator: "\n"))
                    AppButton(appString("retry", "Retry"), kind: .ghost) { state.loadTeam(bugs: bugs, only: Set(failed)) }
                }
                if team.truncated && !team.isLoading {
                    Text(appFormat("leaderTeamTruncated", "Newest %1$@ per person", "\(ZentaoUIState.teamReadCap)"))
                        .font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
                }
            }
            .fixedSize()
        }
    }
}
