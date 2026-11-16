import AppKit
import CoreDomain
import CoreTools
import CoreUI
import FeatureAppUpdate
import FeatureChat
import FeatureConnections
import FeatureMiniApps
import FeatureNotifications
import FeatureTicketEditor
import FeatureTranslation
import FeatureWorkspaceOverview
import Foundation
import SharedKit
import SwiftUI
import ToolZenTao

/// Fills `ShellModel.host` (and the detail panel's hooks) with the features' views — the shell itself imports none of
/// them. Everything captured is owned by `CompositionRoot`, which lives as long as the app.
@MainActor
struct HostWiring {
    let root: CompositionRoot

    func install() {
        let r = root, shell = root.shell
        var host = ShellHost()
        host.chatUnread = { r.chat.unread.counts[$0] ?? 0 }
        host.chatTotalUnread = { r.chat.unread.total }
        host.chatView = { AnyView(ChatRootView(account: $0, events: r.chat.events)) }
        host.workspacePage = { section in
            switch section {
            case "settings": AnyView(WorkspaceSettingsPage(shell: shell, connections: r.connections))
            default:
                AnyView(WorkspaceOverviewHost(model: r.overview.model, onConnect: { shell.connectRequested = true }) {
                    r.connections.integrationsContent(workspaceId: shell.workspace?.id)
                }.id(r.overview.workspaceId))
            }
        }
        host.settingsPage = { AnyView(SettingsPages(root: r, section: $0)) }
        host.miniAppRail = { AnyView(MiniAppRailSection(feature: r.miniApps, nav: shell.nav)) }
        host.miniAppStack = { AnyView(MiniAppsHostStack()) }
        host.editor = { AnyView(TicketEditorView(route: $0, nav: shell.nav)) }
        if let n = r.notifications {
            host.bell = { AnyView(NotificationsBellButton(model: n)) }
            host.dismissOverlay = { if n.panelOpen { n.closePanel(); return true } else { return false } }
            host.overlay = { inset in AnyView(NotificationsPanel(model: n, leftInset: inset, dateFormat: shell.settings.dateFormat)) }
        }
        host.updateButton = { AnyView(UpdateRailButton(model: r.update)) }
        host.banner = { AnyView(UpdateBannerView(model: r.update)) }
        host.quickSettings = { AnyView(QuickSettingsView(root: r)) }
        host.miniAppName = { id in r.miniApps.model.apps.first { $0.id == id }?.name }
        host.newTicketTargets = { Self.newTicketTargets(shell) }
        shell.host = host
        installDetailExtensions()
        r.miniApps.model.requestShow = { shell.nav.openMiniApp($0) }
        r.miniApps.model.bringToFront = { NSApp.activate(); NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil) }
    }

    /// The "+" menu: a new bug and a new task per ZenTao account of the active workspace, filed into the product / execution
    /// its open section is scoped to (`location.scopeId` on Bugs / Tasks), else ZenTao's current one (`"0"`); either can be
    /// changed in the editor.
    static func newTicketTargets(_ shell: ShellModel) -> [NewTicketTarget] {
        shell.workspaceAccounts.filter { $0.providerType == .zentao }.flatMap { a -> [NewTicketTarget] in
            let location = shell.nav.location(for: a.id)
            let product = location.section == ZentaoSection.bugs ? location.scopeId : nil
            let execution = location.section == ZentaoSection.tasks ? location.scopeId : nil
            return [
                NewTicketTarget(accountId: a.id, accountHandle: a.handle, isBug: true,
                                route: .newBug(accountId: a.id, productId: product ?? "0")),
                NewTicketTarget(accountId: a.id, accountHandle: a.handle, isBug: false,
                                route: .newTask(accountId: a.id, executionId: execution ?? "0")),
            ]
        }
    }

    private func installDetailExtensions() {
        let r = root, shell = root.shell
        var ext = DetailExtensions()
        ext.translationTabLabel = {
            let l = translationLanguage(for: shell.settings.translationLang)
            return "\(l.flag) \(l.nativeName)"
        }
        let hub = TranslationHub(feature: r.translation, settings: { shell.settings }, gate: .shared)
        OpenCodeLinkGate.shared.install(feature: r.translation) { shell.nav.select(.settings); shell.nav.setSettingsSection("translation") }
        ext.translationTab = { ticket, layout in AnyView(TranslationTabView(ticket: ticket, layout: layout, hub: hub, shell: shell).id(ticket.id)) }
        ext.translationFooter = { ticket in AnyView(TranslationFooterView(ticket: ticket, hub: hub, shell: shell).id(ticket.id)) }
        let editor = r.services.zentaoEditor
        if let editor {
            ext.uploadImage = { ticket, data, name in
                await editor.uploadImage(accountId: ticket.accountId, uid: UUID().uuidString, bytes: data, fileName: name).value
            }
            // One upload uid per composer (the comment editor passes its own), so a comment's images group on the server.
            ext.uploadImageWithUid = { ticket, uid, data, name in
                await editor.uploadImage(accountId: ticket.accountId, uid: uid, bytes: data, fileName: name).value
            }
        }
        shell.detail.extensions = ext
    }
}

/// The three environment hooks the boards and the detail panel read, plus everything the features read from the
/// environment (services, chat, mini apps, toasts come from `AppShell`).
struct RootEnvironment: ViewModifier {
    let root: CompositionRoot
    let theme: AppTheme

    func body(content: Content) -> some View {
        let r = root, translation = r.translation
        content
            .environment(\.appTheme, theme)
            .openCodeLinkGate(.shared)
            .environment(\.services, r.services)
            .environment(\.chatServices, r.chat.services)
            .environment(\.chatSettings, ChatSettings(r.shell.settings))
            .environment(\.miniApps, r.miniApps)
            .environment(\.ticketEditorNav, r.shell.nav)
            .environment(\.ticketCardAccessory, { ticket in
                AnyView(TranslationDot(ticket: ticket, feature: translation))
            })
            .environment(\.personAvatar, { req in
                AnyView(ChatPersonAvatar(accountId: req.accountId, name: req.name, diameter: req.diameter))
            })
            .environment(\.personChip, { req in
                AnyView(ChatPersonChip(accountId: req.accountId, name: req.name, diameter: req.diameter))
            })
            // ZenTao documents: the author's chat photo, and a "Message" button beside each person of the people card.
            .environment(\.zentaoCelebrate, { r.shell.celebrate() })
            .environment(\.zentaoDocPersonFace, { f in AnyView(ChatPersonAvatar(accountId: f.accountId, name: f.name, diameter: f.diameter)) })
            .environment(\.zentaoDocPersonAction, { f in AnyView(ChatPersonChatButton(accountId: f.accountId, name: f.name)) })
    }
}

extension View {
    func rootEnvironment(_ root: CompositionRoot, theme: AppTheme) -> some View { modifier(RootEnvironment(root: root, theme: theme)) }
}
