import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: app/shell/app_nav_rail.dart (76pt). Workspace, Chat (unread), one button per account (ZenTao ones carry
/// their chat's unread count), "+ Connect", the mini apps, the notifications bell, the update button and Settings.
/// Each place opens with a keyboard shortcut too (`RailPlace`, ⌘1 … ⌘0 then ⌥⌘1 … ⌥⌘0 from the top unless chosen otherwise), shown in its
/// tooltip and, while the shortcut's modifiers are held, on the button itself (`RailKeyHints`).
struct NavRail: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel

    var body: some View {
        let host = model.host, nav = model.nav, onScreen = !model.miniAppOnScreen
        let keys = model.railShortcuts
        VStack(spacing: theme.spacing.s2) {
            NewTicketRailButton(model: model)
            RailLabeledButton(appString("dashboard", "Dashboard"), systemImage: "square.grid.2x2",
                              selected: onScreen && nav.state.rail == .workspace,
                              help: tip(appString("dashboard", "Dashboard"), onScreen && nav.state.rail == .workspace, keys[RailPlace.workspace])) {
                model.railTap(isCurrent: nav.state.rail == .workspace) { nav.select(.workspace) }
            }
            .railKeyHint(model.railKeyHint(RailPlace.workspace, keys: keys))
            if model.chatAccount != nil {
                RailLabeledButton(appString("chat", "Chat"), systemImage: "bubble.left.and.bubble.right",
                                  selected: onScreen && nav.state.rail == .chat, badge: host.chatTotalUnread(),
                                  help: tip(appString("chat", "Chat"), onScreen && nav.state.rail == .chat, keys[RailPlace.chat]),
                                  brand: model.chatAccount?.providerType) {
                    model.railTap(isCurrent: nav.state.rail == .chat) { nav.select(.chat) }
                }
                .railKeyHint(model.railKeyHint(RailPlace.chat, keys: keys))
            }
            ForEach(model.railSectionTools, id: \.module.providerType) { entry in
                ForEach(entry.module.sections.filter(\.available)) { section in
                    let current = sectionSelected(entry.module, section)
                    RailLabeledButton(appString(section.label, section.label.capitalized), systemImage: section.systemImage,
                                      selected: current,
                                      help: tip(appString(section.label, section.label.capitalized), current, keys[RailPlace.section(entry.module.providerType, section.id)]),
                                      brand: entry.module.providerType) {
                        model.railTap(isCurrent: current) { model.openRailSection(section.id, tool: entry.module, accounts: entry.accounts) }
                    }
                    .railKeyHint(model.railKeyHint(RailPlace.section(entry.module.providerType, section.id), keys: keys))
                }
            }
            RailDivider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: theme.spacing.s2) {
                    ForEach(model.railAccounts) { a in
                        RailAccountButton(account: a, duplicate: model.railAccounts.filter { $0.providerType == a.providerType }.count > 1,
                                          selected: onScreen && nav.state.rail == .account(a.id), badge: host.chatUnread(a.id),
                                          folded: onScreen && nav.state.rail == .account(a.id) ? model.currentPaneFolded : nil,
                                          keys: keys[RailPlace.account(a.id)]) {
                            model.railTap(isCurrent: nav.state.rail == .account(a.id)) { nav.select(.account(a.id)) }
                        }
                        .railKeyHint(model.railKeyHint(RailPlace.account(a.id), keys: keys))
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
                              selected: onScreen && nav.state.rail == .settings,
                              help: tip(appString("settings", "Settings"), onScreen && nav.state.rail == .settings, keys[RailPlace.settings])) {
                model.railTap(isCurrent: nav.state.rail == .settings) { nav.select(.settings) }
            }
            .railKeyHint(model.railKeyHint(RailPlace.settings, keys: keys))
        }
        .padding(.bottom, theme.spacing.s12).padding(.top, theme.sizes.titleBar - theme.spacing.s8)
        .frame(width: theme.sizes.rail).frame(maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxX } action: { model.railEdge = $0 }
    }

    /// The tooltip of a place's button: its name and, for the place on screen, what a second click does to its side panel.
    private func tip(_ name: String, _ current: Bool, _ keys: KeyShortcut?) -> String {
        RailTips.place(name, current: current, folded: model.currentPaneFolded, keys: keys)
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
    let account: Account; let duplicate: Bool; let selected: Bool; let badge: Int
    /// Whether the side panel of this account (the one on screen) is folded; nil for an account that is not on screen.
    var folded: Bool?
    var keys: KeyShortcut?
    let action: () -> Void
    var body: some View {
        RailLabeledButton(label: duplicate ? account.handle : account.providerType.displayName, selected: selected, badge: badge,
                          help: RailTips.place("\(account.providerType.displayName) · \(account.handle)", current: folded != nil, folded: folded ?? false, keys: keys),
                          action: action) {
            BrandLogoBadge(account.providerType, size: 22)
        }
    }
}

/// What a rail button says when the pointer rests on it.
enum RailTips {
    /// `name`, and for the place on screen the second click: "Click again to hide / show the side panel".
    /// `keys` (the place's keyboard shortcut) follows the name in brackets.
    static func place(_ name: String, current: Bool, folded: Bool, keys: KeyShortcut? = nil) -> String {
        let name = keys.map { "\(name) (\($0.display))" } ?? name
        guard current else { return name }
        return name + " · " + (folded ? appString("railShowPanel", "click again to show the side panel") : appString("railHidePanel", "click again to hide the side panel"))
    }
}
