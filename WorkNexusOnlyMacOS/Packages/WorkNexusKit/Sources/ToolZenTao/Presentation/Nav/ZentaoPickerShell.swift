import CoreUI
import SwiftUI

/// Ported from: lib/tools/zentao/presentation/widgets/{zentao_product_popover,zentao_execution_popover,zentao_popover_tab_button}.dart
/// The card the product and execution pickers share: a search field, the Mine / Others tabs ("Mine" is where the
/// user has work) and the list under them. The owner keeps the search text and the tab.
struct ZentaoPickerShell<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let searchHint: String
    @Binding var search: String
    @Binding var tab: ZentaoPickerTab
    let content: Content

    init(searchHint: String, search: Binding<String>, tab: Binding<ZentaoPickerTab>, @ViewBuilder content: () -> Content) {
        self.searchHint = searchHint; _search = search; _tab = tab; self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            AppSearchField(text: $search, hint: searchHint, autofocus: true)
                .padding(.horizontal, theme.spacing.s10).padding(.top, theme.spacing.s10).padding(.bottom, theme.spacing.s6)
            HStack(spacing: theme.spacing.s12) {
                ZentaoPopoverTabButton(label: appString("zentaoPickerMine", "Mine"), active: tab == .mine) { tab = .mine }
                ZentaoPopoverTabButton(label: appString("zentaoPickerOthers", "Others"), active: tab == .others) { tab = .others }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing.s10)
            .overlay(alignment: .bottom) { Divider().overlay(theme.colors.line) }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Self.width, height: theme.sizes.dialogSm)
    }

    /// The card's width (its height is a small dialog's).
    static var width: CGFloat { 340 }
}

/// One tab of the picker: its label with an accent underline while active.
struct ZentaoPopoverTabButton: View {
    @Environment(\.appTheme) private var theme
    let label: String; let active: Bool; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            Text(label).font(theme.typography.label).foregroundStyle(active ? theme.colors.accent : theme.colors.tx2)
                .padding(.vertical, theme.spacing.s6)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(active ? theme.colors.accent : .clear).frame(height: theme.borders.thick)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The small "Product" / "Project" tag at the end of a picker row.
struct ZentaoKindTag: View {
    @Environment(\.appTheme) private var theme
    let text: String; var highlighted = false
    var body: some View {
        Text(text).font(theme.typography.caption).foregroundStyle(highlighted ? theme.colors.accent : theme.colors.tx3)
            .padding(.horizontal, theme.spacing.s4).padding(.vertical, 1)
            .background(highlighted ? theme.colors.accent.opacity(0.15) : theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.xs))
    }
}

/// The picker's empty state: an icon and a line ("No products found").
struct ZentaoPickerEmpty: View {
    @Environment(\.appTheme) private var theme
    let systemImage: String; let text: String
    var body: some View {
        VStack(spacing: theme.spacing.s8) {
            Image(systemName: systemImage).font(.system(size: theme.sizes.icon24)).foregroundStyle(theme.colors.tx3)
            Text(text).font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
        }
        .padding(theme.spacing.s24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
