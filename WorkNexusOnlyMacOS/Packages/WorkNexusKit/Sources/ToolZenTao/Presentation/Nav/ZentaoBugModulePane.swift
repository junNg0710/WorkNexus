import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/zentao/presentation/nav/zentao_bug_module_pane.dart
/// The Bugs side panel: the pinned products (and the open one), a picker for any other, then the open product's
/// module tree, which narrows the board like ZenTao's own.
struct ZentaoBugModulePane: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState
    let account: Account
    let location: ToolLocation

    var body: some View {
        let pinned = state.bugBoard.settings.pinnedProjects
        let rows = ZentaoNavLogic.productRows(products: state.products[account.id]?.value ?? [], pinned: pinned,
                                              accountId: account.id, openId: location.scopeId)
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScopeGroupHeader(title: appString("zentaoProductsGroup", "Products"))
                    ForEach(rows) { p in
                        let isPinned = pinned.contains(ZentaoNavLogic.productKey(accountId: account.id, productId: p.id))
                        ScopeEntryRow(name: p.name, systemImage: "shippingbox", selected: p.id == location.scopeId, isPinned: isPinned,
                                      onPinToggle: { state.togglePinnedProduct(accountId: account.id, productId: p.id) },
                                      onTap: { state.openProduct(p) })
                    }
                    ZentaoScopePickerRow(label: appString("zentaoOtherProducts", "Other products…")) { close in
                        ZentaoProductPopover(state: state, account: account, onClose: close)
                    }
                    Spacer().frame(height: theme.spacing.s8)
                    ZentaoModuleTreeSection(state: state, bugs: true)
                }
                .padding(EdgeInsets(top: theme.spacing.s4, leading: theme.spacing.s8, bottom: theme.spacing.s16, trailing: theme.spacing.s8))
            }
            ZentaoHideEmptyModulesToggle(state: state)
        }
        .task { state.loadProducts(account.id) }
    }
}
