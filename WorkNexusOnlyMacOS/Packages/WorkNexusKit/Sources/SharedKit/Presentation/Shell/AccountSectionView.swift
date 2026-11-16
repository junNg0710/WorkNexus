import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/app/shell/viewport.dart `_buildAccountSection` + section_error_boundary.dart.
/// One tool section with what the shell knows about its account: the expired-session banner, the offline / failed-sync
/// strip, and — when a sync failed and nothing is cached yet — an error state with Retry over the (still mounted) section
/// instead of a blank board.
struct AccountSectionView: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel
    let account: Account
    let section: AnyView

    var body: some View {
        let status = model.syncStatus(of: account.id)
        let health = SectionHealth(status: status, hasCachedData: hasCachedData(status))
        VStack(spacing: 0) {
            AccountBanners(model: model, account: account, health: health)
            ZStack {
                section
                if health.blocksSection {
                    SectionErrorBoundary(message: message(health)) { retry() }.background(theme.colors.bg)
                }
            }
        }
    }

    /// Only looked at while the account is in trouble (it scans the tickets, and registers the dependency).
    private func hasCachedData(_ status: AccountSyncStatus?) -> Bool {
        switch status {
        case .offline?, .error?: model.detail.tickets.values.contains { $0.accountId == account.id }
        default: true
        }
    }

    private func message(_ health: SectionHealth) -> String {
        switch health {
        case .failed(let m, _): appFormat("syncFailedBanner", "Couldn't sync %1$@: %2$@", account.handle, m)
        default: appString("syncOfflineEmpty", "You're offline and nothing is saved for this account yet.")
        }
    }

    private func retry() { Task { _ = await model.services.sync.sync(accountId: account.id) } }
}

/// Ported from: lib/app/shell/section_error_boundary.dart. A section that could not be shown: the error and a Retry, with
/// the rail and pane still usable. (Swift views cannot throw while building, so this stands in for the places the Flutter
/// boundary caught: an account that has no tool, a sync that failed before anything was stored.)
public struct SectionErrorBoundary: View {
    let message: String; let onRetry: () -> Void
    public init(message: String, onRetry: @escaping () -> Void) { self.message = message; self.onRetry = onRetry }
    public var body: some View { AppStateView(.error(message), retry: onRetry) }
}
