import CoreUI
import SwiftUI

/// The tabs of a mini app, Safari-style, under the browser bar: the app's icon (a spinner while the page loads) and the page's
/// title on each, a close mark once there is more than one, and "+" for a new tab on the app's address.
struct MiniAppTabStrip: View {
    @Environment(\.appTheme) private var theme
    let app: MiniApp
    let tabs: MiniAppTabsModel

    var body: some View {
        // "+" sits right after the last tab while they fit; once they do not, the tabs scroll and "+" stays at the end.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: theme.spacing.s4) {
                items
                newTabButton
                Spacer(minLength: 0)
            }
            HStack(spacing: theme.spacing.s4) {
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: theme.spacing.s4) { items } }
                newTabButton
            }
        }
        .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s4)
        .background(theme.colors.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
    }
}

private extension MiniAppTabStrip {
    @ViewBuilder var items: some View {
        ForEach(tabs.tabs) { tab in
            MiniAppTabItem(app: app, tab: tab, selected: tab.id == tabs.selectedId, closable: tabs.canCloseTab,
                           onSelect: { tabs.select(tab.id) }, onClose: { tabs.close(tab.id) })
        }
    }

    var newTabButton: some View {
        MiniAppStripButton(symbol: "plus", help: appString("miniAppNewTab", "New tab")) { tabs.newTab(url: app.url) }
            .disabled(!tabs.canOpenTab).opacity(tabs.canOpenTab ? 1 : 0.4)
    }
}

/// One tab: its icon or spinner, its title and, once hovered or selected, its close mark.
struct MiniAppTabItem: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let app: MiniApp
    let tab: MiniAppBrowserModel
    let selected: Bool
    let closable: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    /// The page's title, else its site.
    private var label: String {
        if !tab.title.isEmpty { return tab.title }
        return URL(string: tab.address)?.host ?? app.name
    }

    var body: some View {
        HStack(spacing: theme.spacing.s6) {
            Group {
                if tab.loading { ProgressView().controlSize(.mini) } else { MiniAppIconView(app: app, size: theme.sizes.icon14) }
            }
            .frame(width: theme.sizes.icon14, height: theme.sizes.icon14)
            Text(label).font(theme.typography.meta).foregroundStyle(selected ? theme.colors.tx : theme.colors.tx2)
                .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            if closable {
                MiniAppStripButton(symbol: "xmark", help: appString("miniAppCloseTab", "Close tab"), size: 16, onTap: onClose)
                    .opacity(selected || hovering ? 1 : 0)
            }
        }
        .padding(.horizontal, theme.spacing.s8).frame(minWidth: 110, idealWidth: 160, maxWidth: 200).frame(height: 28)
        .background(selected ? theme.colors.card : (hovering ? theme.colors.panel2 : .clear), in: RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(selected ? theme.colors.line : .clear, lineWidth: theme.borders.hairline))
        .contentShape(RoundedRectangle(cornerRadius: theme.radii.md))
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
        .contextMenu {
            if closable { Button(appString("miniAppCloseTab", "Close tab"), action: onClose) }
        }
        .help(label)
        .accessibilityElement(children: .combine).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A small round icon button of the tab strip.
struct MiniAppStripButton: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let symbol: String
    let help: String
    var size: CGFloat = 24
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: symbol).font(.system(size: theme.sizes.icon12, weight: .semibold))
                .foregroundStyle(hovering ? theme.colors.tx : theme.colors.tx2)
                .frame(width: size, height: size)
                .background(hovering ? theme.colors.tx.opacity(0.1) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }.help(help)
    }
}
