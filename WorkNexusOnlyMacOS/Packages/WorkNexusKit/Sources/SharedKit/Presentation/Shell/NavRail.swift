import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: app/shell/app_nav_rail.dart (76pt). Workspace, Chat (unread), one button per account (ZenTao ones carry
/// their chat's unread count), "+ Connect", the mini apps, the notifications bell, the update button and Settings.
/// ⌘1 = workspace, ⌘2…⌘9 = the accounts in order.
struct NavRail: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel

    var body: some View {
        let host = model.host, nav = model.nav, onScreen = !model.miniAppOnScreen
        VStack(spacing: theme.spacing.s2) {
            NewTicketRailButton(model: model)
            RailLabeledButton(appString("dashboard", "Dashboard"), systemImage: "square.grid.2x2",
                              selected: onScreen && nav.state.rail == .workspace, help: tip(appString("dashboard", "Dashboard"), onScreen && nav.state.rail == .workspace)) {
                model.railTap(isCurrent: nav.state.rail == .workspace) { nav.select(.workspace) }
            }
                .keyboardShortcut("1", modifiers: .command)
            if model.chatAccount != nil {
                RailLabeledButton(appString("chat", "Chat"), systemImage: "bubble.left.and.bubble.right",
                                  selected: onScreen && nav.state.rail == .chat, badge: host.chatTotalUnread(),
                                  help: tip(appString("chat", "Chat"), onScreen && nav.state.rail == .chat),
                                  brand: model.chatAccount?.providerType) {
                    model.railTap(isCurrent: nav.state.rail == .chat) { nav.select(.chat) }
                }
            }
            ForEach(model.railSectionTools, id: \.module.providerType) { entry in
                ForEach(entry.module.sections.filter(\.available)) { section in
                    let current = sectionSelected(entry.module, section)
                    RailLabeledButton(appString(section.label, section.label.capitalized), systemImage: section.systemImage,
                                      selected: current, help: tip(appString(section.label, section.label.capitalized), current),
                                      brand: entry.module.providerType) {
                        model.railTap(isCurrent: current) { model.openRailSection(section.id, tool: entry.module, accounts: entry.accounts) }
                    }
                }
            }
            RailDivider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: theme.spacing.s2) {
                    ForEach(Array(model.railAccounts.enumerated()), id: \.element.id) { i, a in
                        RailAccountButton(account: a, duplicate: model.railAccounts.filter { $0.providerType == a.providerType }.count > 1,
                                          selected: onScreen && nav.state.rail == .account(a.id), badge: host.chatUnread(a.id),
                                          folded: onScreen && nav.state.rail == .account(a.id) ? model.currentPaneFolded : nil) {
                            model.railTap(isCurrent: nav.state.rail == .account(a.id)) { nav.select(.account(a.id)) }
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(min(i + 2, 9))")), modifiers: .command)
                    }
                    RailLabeledButton(appString("railConnect", "Connect"), systemImage: "plus.circle", help: appString("connectATool", "Connect a tool")) {
                        model.connectRequested = true
                    }
                    RailDivider()
                    host.miniAppRail()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            RailDivider()
            host.bell()
            host.updateButton()
            RailLabeledButton(appString("settings", "Settings"), systemImage: "gearshape",
                              selected: onScreen && nav.state.rail == .settings, help: tip(appString("settings", "Settings"), onScreen && nav.state.rail == .settings)) {
                model.railTap(isCurrent: nav.state.rail == .settings) { nav.select(.settings) }
            }
        }
        .padding(.bottom, theme.spacing.s12).padding(.top, theme.sizes.titleBar - theme.spacing.s8)
        .frame(width: theme.sizes.rail).frame(maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxX } action: { model.railEdge = $0 }
    }

    /// The tooltip of a place's button: its name and, for the place on screen, what a second click does to its side panel.
    private func tip(_ name: String, _ current: Bool) -> String { RailTips.place(name, current: current, folded: model.currentPaneFolded) }

    /// A rail section button is selected when the open account belongs to its tool and sits on that section.
    private func sectionSelected(_ module: any ToolModule, _ section: ToolSection) -> Bool {
        guard !model.miniAppOnScreen, case .account(let id) = model.nav.state.rail,
              model.account(id)?.providerType == module.providerType else { return false }
        return model.nav.location(for: id).section == section.id
    }
}

/// One account's rail button: its provider logo, the provider name (the login when two accounts share a provider).
private struct RailAccountButton: View {
    let account: Account; let duplicate: Bool; let selected: Bool; let badge: Int
    /// Whether the side panel of this account (the one on screen) is folded; nil for an account that is not on screen.
    var folded: Bool?
    let action: () -> Void
    var body: some View {
        RailLabeledButton(label: duplicate ? account.handle : account.providerType.displayName, selected: selected, badge: badge,
                          help: RailTips.place("\(account.providerType.displayName) · \(account.handle)", current: folded != nil, folded: folded ?? false),
                          action: action) {
            BrandLogoBadge(account.providerType, size: 22)
        }
    }
}

/// What a rail button says when the pointer rests on it.
enum RailTips {
    /// `name`, and for the place on screen the second click: "Click again to hide / show the side panel".
    static func place(_ name: String, current: Bool, folded: Bool) -> String {
        guard current else { return name }
        return name + " · " + (folded ? appString("railShowPanel", "click again to show the side panel") : appString("railHidePanel", "click again to hide the side panel"))
    }
}
