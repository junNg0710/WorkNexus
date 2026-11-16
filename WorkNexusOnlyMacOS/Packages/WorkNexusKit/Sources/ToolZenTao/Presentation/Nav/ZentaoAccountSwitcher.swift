import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/tools/zentao/presentation/nav/zentao_account_switcher.dart
/// Which ZenTao account the Tasks / Bugs place shows, at the top of its side panel: Tasks and Bugs sit on the rail,
/// not one button per account. Only with two accounts or more; switching keeps the place (Tasks or Bugs).
struct ZentaoAccountSwitcher: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState
    let account: Account
    let section: SectionID

    var body: some View {
        let accounts = ZentaoAccountSwitcher.zentaoAccounts(Array(state.bugBoard.accounts.values))
        if accounts.count >= 2 {
            AppSegmentedTabs(accounts.map { a in
                AppSegmentedTab(label: a.handle, active: a.id == account.id) { switchTo(a) }
            })
            .padding(theme.spacing.s8)
            .overlay(alignment: .bottom) { Divider().overlay(theme.colors.line) }
        }
    }

    /// The ZenTao accounts in the rail's order.
    static func zentaoAccounts(_ all: [Account]) -> [Account] {
        Account.sort(all.filter { $0.providerType == .zentao })
    }

    private func switchTo(_ target: Account) {
        guard target.id != account.id else { return }
        state.deps.nav.select(.account(target.id))
        state.deps.nav.setSection(section, accountId: target.id)
    }
}
