import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/tools/zentao/presentation/widgets/zentao_product_popover.dart (the Bugs header's picker)
/// The Bugs header's `Product › Name ▾` switcher: shows the open product and opens the product picker.
public struct ZentaoProductSwitcher: View {
    let state: ZentaoUIState
    let account: Account

    public init(state: ZentaoUIState, account: Account) { self.state = state; self.account = account }

    public var body: some View {
        let open = state.product?.accountId == account.id ? state.product : nil
        ZentaoSwitcherButton(kind: appString("fieldProduct", "Product"),
                             title: open?.productName ?? appString("zentaoSelectProduct", "Select Product")) { close in
            ZentaoProductPopover(state: state, account: account, onClose: close)
        }
    }
}
