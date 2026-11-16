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
                              selected: onScreen && nav.state.rail == .workspace) { nav.select(.workspace) }
                .keyboardShortcut("1", modifiers: .command)
            if model.chatAccount != nil {
                RailLabeledButton(appString("chat", "Chat"), systemImage: "bubble.left.and.bubble.right",
                                  selected: onScreen && nav.state.rail == .chat, badge: host.chatTotalUnread(),
                                  brand: model.chatAccount?.providerType) { nav.select(.chat) }
            }
            ForEach(model.railSectionTools, id: \.module.providerType) { entry in
                ForEach(entry.module.sections.filter(\.available)) { section in
                    RailLabeledButton(appString(section.label, section.label.capitalized), systemImage: section.systemImage,
                                      selected: sectionSelected(entry.module, section), brand: entry.module.providerType) {
                        model.openRailSection(section.id, tool: entry.module, accounts: entry.accounts)
                    }
                }
            }
            RailDivider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: theme.spacing.s2) {
                    ForEach(Array(model.railAccounts.enumerated()), id: \.element.id) { i, a in
                        RailAccountButton(account: a, duplicate: model.railAccounts.filter { $0.providerType == a.providerType }.count > 1,
                                          selected: onScreen && nav.state.rail == .account(a.id), badge: host.chatUnread(a.id)) {
                            nav.select(.account(a.id))
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
                              selected: onScreen && nav.state.rail == .settings) { nav.select(.settings) }
        }
        .padding(.bottom, theme.spacing.s12).padding(.top, theme.sizes.titleBar - theme.spacing.s8)
        .frame(width: theme.sizes.rail).frame(maxHeight: .infinity)
    }

    /// A rail section button is selected when the open account belongs to its tool and sits on that section.
    private func sectionSelected(_ module: any ToolModule, _ section: ToolSection) -> Bool {
        guard !model.miniAppOnScreen, case .account(let id) = model.nav.state.rail,
              model.account(id)?.providerType == module.providerType else { return false }
        return model.nav.location(for: id).section == section.id
    }
}

/// One account's rail button: its provider logo, the provider name (the login when two accounts share a provider).
private struct RailAccountButton: View {
    let account: Account; let duplicate: Bool; let selected: Bool; let badge: Int; let action: () -> Void
    var body: some View {
        RailLabeledButton(label: duplicate ? account.handle : account.providerType.displayName, selected: selected, badge: badge,
                          help: "\(account.providerType.displayName) · \(account.handle)", action: action) {
            BrandLogoBadge(account.providerType, size: 22)
        }
    }
}
