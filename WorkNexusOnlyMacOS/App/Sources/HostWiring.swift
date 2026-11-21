import AppKit
import CoreDomain
import CoreTools
import CoreUI
import FeatureAppUpdate
import FeatureChat
import FeatureConnections
import FeatureMiniApps
import FeatureNotifications
import FeaturePanicSwitch
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
        host.chatView = { AnyView(ChatRootView(account: $0, events: r.chat.events).modifier(ChatAccountsFromShell(root: r))) }
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
        host.banner = { AnyView(UpdateBannerHost(model: r.update, whatsNew: r.whatsNew)) }
        host.quickSettings = { AnyView(QuickSettingsView(root: r)) }
        host.petSheet = { r.petLibrary.sheet(for: shell.settings.petId) }
        host.petWaiting = { r.notifications?.unreadCount ?? 0 }
        host.petNewestWaiting = { r.notifications?.newestUnread.map { PetNotice(text: $0.text, link: $0.payload) } }
        // A line of the pet's opens what it is about: a chat (`chat:` payload) or a notification's ticket.
        host.petOpen = { link in
            if let app = PetAppLink(link) {
                switch app {
                // A Mac app comes forward over everything (WorkNexus stays where it is).
                case .nativeApp(let id): Task { await r.miniApps.nativeApps.open(id: id) }
                // A web mini app lives in WorkNexus's window: that comes forward on it.
                case .miniApp(let id):
                    NSApp.activate(); _ = r.platform.reopenWindow(); shell.nav.openMiniApp(id)
                }
            } else if link.hasPrefix("chat:") { r.chat.open(payload: link) }
            else if let n = r.notifications { Task { await n.handleTap(payload: link) } }
        }
        host.revealApp = { NSApp.activate(); _ = r.platform.reopenWindow() }
        // The floating pet's panel never takes the app forward by itself, so `isActive` is still what was in front before.
        LastOtherApp.shared.start()
        host.toggleApp = { [weak platform = r.platform] in
            let last = LastOtherApp.shared
            switch PetAppToggle.action(appActive: NSApp.isActive, windowShown: platform?.windowIsShown ?? false,
                                       goesBack: shell.settings.petClickGoesBack, hasPrevious: last.isAvailable) {
            case .hide: NSApp.hide(nil)
            // The app the user was in comes back over WorkNexus, which stays under it as it was.
            case .goBack: if !last.activate() { NSApp.hide(nil) }
            case .bringForward: NSApp.activate(); _ = platform?.reopenWindow()
            }
        }
        // Holding the pet (or two or three quick clicks, as chosen) sets off the panic switch's official trigger, when it is on
        // for this user; "Demo" in its right-click menu sets off the demo trigger while demo mode is on.
        host.petTripleTap = PetTripleTap(armed: {
            switch r.panic.model.petGesture {
            case .hold: .hold(seconds: Double(r.panic.model.config?.petHoldSeconds ?? PanicSwitchConstants.defaultPetHoldSeconds))
            case .doubleClick: .doubleTap
            case .tripleClick: .tripleTap
            case nil: nil
            }
        }, run: { r.panic.model.petTriggered(.release) })
        host.petDemo = { r.panic.model.demoAvailable ? { r.panic.model.petTriggered(.demo) } : nil }
        // The panic switch's settings page is listed only for the ZenTao the feature is offered for.
        host.settingsSectionVisible = { $0 != "panicSwitch" || r.panic.model.account != nil }
        // On the Chat page the title bar searches the chats and their stored messages; a hit opens the chat (at the message).
        let chat = r.chat
        host.placeSearch = { rail in
            guard rail == .chat, let account = shell.chatAccount else { return nil }
            return PlaceSearch(placeholder: appString("chatGlobalSearchHint", "Search chats and messages…")) { query in
                await ChatGlobalSearch(repository: chat.repository, accountId: account.id).search(query).map { hit in
                    PlaceSearchHit(id: hit.id,
                                   section: hit.kind == .chat ? appString("chatGlobalSearchChats", "Chats") : appString("chatGlobalSearchMessages", "Messages"),
                                   icon: hit.kind == .chat ? "bubble.left.and.bubble.right" : "text.bubble", title: hit.title, subtitle: hit.subtitle,
                                   detail: hit.date.map { formatWhen($0) } ?? "") {
                        if let id = hit.serverId { chat.events.open(chatGid: hit.chatGid, jumpTo: id) } else { chat.events.open(chatGid: hit.chatGid) }
                    }
                }
            }
        }
        host.miniAppName = { id in r.miniApps.model.apps.first { $0.id == id }?.name }
        host.newTicketTargets = { Self.newTicketTargets(shell) }
        shell.host = host
        installDetailExtensions()
        r.miniApps.model.requestShow = { shell.nav.openMiniApp($0) }
        // News from the apps on the rail reaches the pet, which opens the app when its line is clicked.
        r.miniApps.model.onNotified = { app, title, body in
            shell.announceApp(app.name, title: title, body: body, link: PetAppLink.miniApp(app.id))
        }
        r.miniApps.nativeApps.readsBadgesInBackground = { shell.settings.showPet && shell.settings.petDisplay == .floating }
        r.miniApps.nativeApps.onBadgeRose = { app, badge in
            shell.announceApp(app.label, badge: badge, link: PetAppLink.nativeApp(app.id))
        }
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
        let hub = TranslationHub(feature: r.translation, aiSetup: r.aiSetup, settings: { shell.settings }, gate: .shared)
        ext.translationTabLabel = { ticket in
            let l = translationLanguage(for: hub.model(for: ticket.id).targetLang)
            return "\(l.flag) \(l.nativeName)"
        }
        ext.translateInto = { ticket in
            let model = hub.model(for: ticket.id)
            return translationLanguages.map { lang in
                AppNativeMenu.Item("\(lang.flag)  \(lang.nativeName)", checked: lang.code == model.targetLang) { model.translate(ticket, into: lang.code) }
            }
        }
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
        // "Share in chat": a ZenTao ticket goes to its own account's chat, anything else to the chat account in use.
        let chatServices = r.chat.services
        ext.shareToChat = { ticket, close in
            guard let url = ticket.url, !url.isEmpty else { return nil }
            let account = ticket.providerType == .zentao ? ticket.accountId : shell.chatAccount?.id
            guard let account else { return nil }
            return AnyView(ChatShareDialog(accountId: account, services: chatServices, text: "\(ticketTitleWithRef(ticket))\n\(url)", onClose: close))
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
            .zentaoTodoPrompt(r.todoPrompt)
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

/// Tells the chat which accounts it can switch between (several ZenTao accounts each log into their own chat): the
/// switch sits at the top of the chat list.
private struct ChatAccountsFromShell: ViewModifier {
    let root: CompositionRoot

    func body(content: Content) -> some View {
        let shell = root.shell, accounts = shell.chatAccounts
        content.chatAccountChoices(accounts.count > 1 ? ChatAccountChoices(
            choices: accounts.map { .init(id: $0.id, name: $0.handle, unread: root.chat.unread.counts[$0.id] ?? 0) },
            currentId: shell.chatAccount?.id, pick: { shell.chatAccountId = $0 }) : nil)
    }
}
