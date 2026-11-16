import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/tools/zentao/presentation/widgets/{zentao_product_popover,zentao_product_popover_list}.dart
/// The picker of the Bugs side panel and header: search, Mine / Others tabs and the account's products with their
/// open bug counts. Picking one opens its bug board and calls `onClose`.
struct ZentaoProductPopover: View {
    let state: ZentaoUIState
    let account: Account
    let onClose: () -> Void
    @State private var search = ""
    @State private var tab = ZentaoPickerTab.mine

    var body: some View {
        let choices = ZentaoNavLogic.productChoices(
            products: state.products[account.id]?.value ?? [], tickets: state.bugBoard.tickets, account: account,
            accountId: account.id, search: search, tab: tab)
        let openId = state.execution == nil ? state.product.flatMap { $0.accountId == account.id ? $0.productId : nil } : nil
        ZentaoPickerShell(searchHint: appString("filterProducts", "Filter products"), search: $search, tab: $tab) {
            ZentaoProductPopoverList(choices: choices, selectedId: openId) { product in
                state.openProduct(product)
                onClose()
            }
        }
        .task { state.loadProducts(account.id) }
    }
}

/// The products of the picker as flat rows (no executions under a product: those belong to projects).
struct ZentaoProductPopoverList: View {
    @Environment(\.appTheme) private var theme
    let choices: [ZentaoProductChoice]
    let selectedId: String?
    let onSelect: (ProviderProduct) -> Void

    var body: some View {
        if choices.isEmpty {
            ZentaoPickerEmpty(systemImage: "shippingbox", text: appString("zentaoNoProductsFound", "No products found"))
        } else {
            ScrollView {
                LazyVStack(spacing: theme.spacing.s2) {
                    ForEach(choices) { choice in
                        ZentaoProductNode(choice: choice, selected: choice.id == selectedId) { onSelect(choice.product) }
                    }
                }
                .padding(.vertical, theme.spacing.s4).padding(.horizontal, theme.spacing.s8)
            }
        }
    }
}

/// A product row of the picker: box icon, name, open count and a "Product" tag.
struct ZentaoProductNode: View {
    @Environment(\.appTheme) private var theme
    let choice: ZentaoProductChoice
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        let c = theme.colors
        HoverSurface(onTap: onTap, selected: selected, cornerRadius: theme.radii.xs) {
            HStack(spacing: theme.spacing.s6) {
                Image(systemName: "shippingbox").font(.system(size: theme.sizes.icon14)).foregroundStyle(selected ? c.accent : c.tx2)
                Text(choice.product.name).font(theme.typography.meta.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? c.accent : c.tx).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if choice.openCount > 0 {
                    Text("\(choice.openCount)").font(theme.typography.mono.weight(.semibold)).foregroundStyle(selected ? c.accent : c.tx3)
                }
                ZentaoKindTag(text: appString("fieldProduct", "Product"), highlighted: selected)
            }
            .padding(.horizontal, theme.spacing.s4).padding(.vertical, theme.spacing.s6)
        }
    }
}
