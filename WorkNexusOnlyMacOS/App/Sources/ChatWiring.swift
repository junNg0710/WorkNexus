import AppKit
import CoreDomain
import CorePersistence
import CoreTools
import CoreUI
import FeatureChat
import FeatureTranslation
import Foundation
import Observation
import SharedKit
import ToolZenTao

/// Chat at the composition root: one repository for every ZenTao account, the services the chat view reads from the
/// environment, the unread counters behind the rail badges, and the bridge that turns incoming messages into OS
/// notifications + the Dock badge (lib/features/chat/** providers + chat_notification_listener).
@MainActor
final class ChatWiring {
    let repository: ChatRepository
    let services: ChatServices
    let unread = ChatUnreadModel()
    let events = ChatShellEvents()
    let dockBadgeBridge = CombinedDockBadge()
    private let appServices: AppServices
    private let shell: ShellModel
    private let notifier: DesktopNotifier
    private let live: LiveSettings
    private let isDemo: Bool
    private var bridge: ChatNotificationBridge?
    private var counters: [String: Task<Void, Never>] = [:]
    private var watcher: Task<Void, Never>?
    private var activeObserver: NSObjectProtocol?

    init(db: AppDatabase, services appServices: AppServices, shell: ShellModel, notifier: DesktopNotifier,
         translation: TranslationFeature, live: LiveSettings, todoPrompt: ZentaoTodoPrompt, isDemo: Bool) {
        self.appServices = appServices; self.shell = shell; self.notifier = notifier; self.live = live; self.isDemo = isDemo
        let repo = ChatFeature.makeRepository(db: db, credentials: appServices.credentials)
        repository = repo
        let tickets = appServices.tickets
        let nav = shell.nav
        // The services are built before `self` is complete, so the "show a chat" hook reaches `self` through a relay.
        let relay = ShowChatRelay()
        services = ChatFeature.makeServices(
            repository: repo, db: db, credentials: appServices.credentials,
            bundledStickers: Bundle.main.url(forResource: "Stickers", withExtension: nil),
            translator: TranslationChatAdapter(service: translation.service),
            ensureTranslatorReady: { await OpenCodeLinkGate.shared.ensureLinked() },
            // The ✨ AI help (summaries, reply ideas, rewrites) runs on the translation service, routed to the provider + model
            // chosen for AI in chat; its summaries can be written in any of the translation languages.
            ai: TranslationChatAiTextGenerator(service: translation.service),
            // The AI help may run on another provider than translation (Settings → Translation → AI in chat).
            ensureAiReady: { await OpenCodeLinkGate.shared.ensureLinked(.chat) },
            aiLanguages: translationLanguages.map { ChatAiLanguage(code: $0.code, englishName: $0.englishName, nativeName: $0.nativeName, flag: $0.flag) },
            setStickerSuggestions: { on in Task { @MainActor in shell.updateSettings { $0.chatStickerSuggestions = on } } },
            setReplyRole: { role in Task { @MainActor in shell.updateSettings { $0.chatAiReplyRole = role.rawValue } } },
            ticketLookup: { url in
                var it = tickets.watchTickets().makeAsyncIterator()
                return await it.next()?.first { $0.url == url }
            },
            mergeRequests: MergeRequestLinkFetcher(workspaces: appServices.workspaces, tickets: tickets, credentials: appServices.credentials,
                                                   sync: appServices.sync),
            showChat: { accountId, gid in relay.call(accountId, gid) },
            openTicket: { ticket in Task { @MainActor in nav.openTicket(ticket.id) } },
            // The profile popup: a colleague's ZenTao profile, and their open synced bugs and tasks.
            people: ZentaoModuleData.personDirectory(sync: appServices.sync, workspaces: appServices.workspaces),
            watchTickets: { tickets.watchTickets() })
        relay.handler = { [weak self] accountId, gid in Task { @MainActor in self?.show(accountId: accountId, chatGid: gid) } }
        events.onViewProfile = { _ in nav.setWorkspaceSection("integrations") }
        events.onOpenStorage = { nav.select(.settings); nav.setSettingsSection("cache") }
        // A message sent: the title bar's search, left open over the chat, is put away.
        events.onMessageSent = { [shell] in shell.searchDismissTick += 1 }
        events.onEnableNotifications = { [weak self] in Task { await self?.turnOnNotifications() } }
        // "Create bug / task / todo" on a message: the chat's account is a ZenTao account, so the ticket is made there.
        // A bug or a task opens the full editor with the message filled in (product / execution are picked there); a
        // todo is small enough for a dialog.
        events.onCreateTicket = { request in
            let seed = request.seed
            // The pictures among the messages go along; the editor uploads them into the new ticket's body.
            let prefill = TicketEditorPrefill(title: seed.title, bodyHtml: seed.html, pictures: seed.pictures.map {
                TicketEditorPrefill.Picture(token: $0.token, name: $0.name, data: $0.data)
            })
            switch request.kind {
            case .bug: nav.openEditor(.newBug(accountId: request.accountId, productId: "0"), prefill: prefill)
            case .task: nav.openEditor(.newTask(accountId: request.accountId, executionId: "0"), prefill: prefill)
            case .todo:
                todoPrompt.open(accountId: request.accountId, name: seed.title, desc: seed.text)
            }
        }
    }

    /// Whether the warning strip ("notifications are blocked") shows: chat notifications are on in the app but the OS does not
    /// let the app raise them (`DesktopNotifier.permissionGranted` is nil when that cannot be known: no strip then).
    func refreshNotificationPermission(wanted: Bool? = nil) async {
        guard !isDemo else { return }
        let wanted = wanted ?? live.value.chatNotifications
        let granted = wanted ? await notifier.permissionGranted() : nil
        events.notificationsBlocked = wanted && granted == false
    }

    /// "Turn on" in the strip: ask again, or — as macOS asks only once — open System Settings (chat_notification_banner.dart `_turnOn`).
    private func turnOnNotifications() async {
        if !(await notifier.requestPermission()) { notifier.openSystemSettings() }
        await refreshNotificationPermission()
    }

    /// Signs every chat account out and in again — after the local chat cache was cleared, so the conversations, contacts and
    /// the open chat's messages fill from the server (lib/app/shell/reload_after_cache_clear.dart, `CacheSection.chat`).
    func reconnectAll() async {
        guard !isDemo else { return }
        let ids = Array(counters.keys)
        for id in ids {
            await repository.disconnect(accountId: id)
            _ = await repository.connect(accountId: id)
        }
    }

    /// Pushes the chat runtime settings (cache size, video auto-download, reactions) into the repository.
    func apply(_ s: AppSettings) {
        repository.setCacheLimit(bytes: s.chatCacheLimitMb * 1024 * 1024)
        repository.setVideoAutoDownloadLimit(bytes: s.chatAutoDownloadVideoMb * 1024 * 1024)
        repository.setReactions(s.chatReactions)
        Task { await refreshNotificationPermission(wanted: s.chatNotifications) }
    }

    /// Signs every ZenTao account into its chat, counts unread messages and raises notifications; follows accounts that
    /// are added or removed later. Not run in demo mode (no chat server to reach).
    func start() async {
        apply(live.value)
        let sink = ChatNotificationSinkImpl(notifier: notifier, shell: shell, live: live)
        bridge = ChatFeature.notificationBridge(
            repository: repository, sink: sink, texts: Self.texts,
            preferences: { [live] in
                let s = live.value
                // The pet hears of new messages too (when it says what they say), even with system notifications off.
                return ChatNotificationPreferences(enabled: s.chatNotifications || (s.showPet && s.petShowsDetails),
                                                   whileViewing: s.chatNotifyWhileViewing, reactions: s.chatReactions)
            },
            // Only the chat open on screen counts as looked at (the Chat place showing, the app in front is checked by the
            // rule); a notification for any other chat comes through even while the Chat place is focused.
            visibleChat: { [events, shell] in
                onMain { shell.nav.rail == .chat && !shell.miniAppOnScreen } ? events.openChat : nil
            })
        watcher = Task { [weak self] in
            guard let accounts = self?.appServices.workspaces.watchAccounts() else { return }
            for await list in accounts { await self?.follow(list.filter { $0.providerType == .zentao }) }
        }
        Task { [weak self] in
            guard let self else { return }
            for await payload in notifier.taps { openFromTap(payload) }
        }
        dockBadgeBridge.setChatUnread { [unread] in unread.total }
        // Coming back from System Settings (or any other app) checks the permission again.
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshNotificationPermission() }
        }
        await refreshNotificationPermission()
    }

    private func follow(_ accounts: [Account]) async {
        let ids = Set(accounts.map(\.id))
        for (id, task) in counters where !ids.contains(id) { task.cancel(); counters[id] = nil; unread.counts[id] = nil }
        bridge?.start(accountIds: accounts.map(\.id))
        for a in accounts where counters[a.id] == nil {
            let counter = ChatFeature.unreadCounter(repository: repository)
            counters[a.id] = Task { [weak self] in
                for await n in counter.counts(accountId: a.id) {
                    self?.unread.counts[a.id] = n
                    self?.dockBadgeBridge.refresh()
                }
            }
            Task { [repository] in _ = await repository.connect(accountId: a.id) }
        }
    }

    /// Shows a chat from a person chip: a detail open over the chat would stay on top of the chat it opens, so it closes;
    /// one on another place waits there (lib/features/chat/presentation/widgets/chat_person_chip.dart `openDirectChatWith`).
    func show(accountId: String, chatGid: String) {
        if shell.nav.rail == .chat { shell.nav.closeTicket() }
        shell.chatAccountId = accountId
        shell.nav.select(.chat)
        events.open(chatGid: chatGid)
    }

    /// A clicked chat notification: the app comes forward on that chat.
    private func openFromTap(_ payload: String) { open(payload: payload) }

    /// Opens the chat a `chat:<accountId>:<chatGid>` payload names (a notification tapped, the pet's line clicked) and
    /// brings the window forward.
    func open(payload: String) {
        let parts = payload.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "chat" else { return }
        shell.chatAccountId = parts[1]
        shell.nav.select(.chat)
        events.open(chatGid: parts[2])
        NSApp.activate()
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }

    private static var texts: ChatNotificationTexts {
        var t = ChatNotificationTexts()
        t.photo = appString("chatPhoto", t.photo); t.file = appString("chatFile", t.file); t.message = appString("chatNewMessage", t.message)
        t.sticker = appString("chatSticker", t.sticker)
        return t
    }
}

/// Unread chat messages per ZenTao account (rail badges, Chat button).
@MainActor @Observable
final class ChatUnreadModel {
    var counts: [String: Int] = [:]
    var total: Int { counts.values.reduce(0, +) }
}

/// The Dock badge shows ZenTao web notifications plus unread chat messages; each half reports separately.
@MainActor
final class CombinedDockBadge: DockBadging {
    private let dock = DockBadge()
    private var web = 0
    private var chatUnread: () -> Int = { 0 }
    func setChatUnread(_ f: @escaping () -> Int) { chatUnread = f; refresh() }
    func show(_ count: Int) { web = count; refresh() }
    func refresh() { dock.show(web + chatUnread()) }
}

/// Adapts FeatureTranslation's service to the chat's own `ChatTextTranslator` (features never import each other).
struct TranslationChatAdapter: ChatTextTranslator {
    let service: TranslationService
    func translateText(key: String, text: String, targetLang: String, model: String?) async -> Outcome<(text: String, model: String?)> {
        switch await service.translateText(key: key, text: text, targetLang: targetLang, model: model) {
        case .success(let t): .success((text: t.text, model: t.model))
        case .failure(let f): .failure(f)
        }
    }
}

/// Lets the chat's AI features (summaries, reply ideas, rewrites) run on the translation backend the user set up, without chat
/// depending on the translation feature: the composition root is the one place that knows both.
/// Ported from: lib/app/di/translation_chat_ai_text_generator.dart
struct TranslationChatAiTextGenerator: ChatAiTextGenerator {
    let service: TranslationService
    func generate(key: String, prompt: String, model: String?) async -> Outcome<ChatAiReply> {
        await service.complete(key: key, prompt: prompt, model: model).map { ChatAiReply($0.text, model: $0.model) }
    }
    func cancel(_ key: String) async { await service.cancel(key) }
}

/// Chat -> OS notifications, and the pet. Whether a message deserves one (not the chat the user is looking at, unless
/// "notify while viewing" is on) was decided by the bridge's `ShouldNotifyChatMessage`; this raises the notification when
/// chat notifications are on, and hands the message to the pet when it says what messages say (`petShowsDetails`).
final class ChatNotificationSinkImpl: ChatNotificationSink, @unchecked Sendable {
    private let notifier: DesktopNotifier
    private let shell: ShellModel
    private let live: LiveSettings

    init(notifier: DesktopNotifier, shell: ShellModel, live: LiveSettings) {
        self.notifier = notifier; self.shell = shell; self.live = live
    }

    var appIsFocused: Bool { onMain { NSApp.isActive && NSApp.keyWindow != nil } }

    func deliver(_ n: ChatNotification) {
        let s = live.value
        if s.showPet && s.petShowsDetails {
            let shell = shell
            let link = "chat:\(n.accountId):\(n.chatGid)"
            Task { @MainActor in shell.announceChat(title: n.title, sender: n.subtitle, body: n.body, link: link) }
        }
        guard s.chatNotifications else { return }
        let title = n.title, body = n.subtitle.map { "\($0): \(n.body)" } ?? n.body
        let id = n.chatGid.hashValue & 0x7fffffff, payload = "chat:\(n.accountId):\(n.chatGid)"
        Task { await notifier.show(id: id, title: title, body: body, payload: payload) }
    }

    func clear(accountId: String, chatGid: String) {}
}

/// Loads the GitLab merge request / GitHub pull request — or an issue of either — a chat link points to: the connected account
/// whose host matches fetches it through its (pooled) adapter, and it is stored with the other tickets, so the chat card and
/// the detail panel read it from the database (lib/shared/sync/data/merge_request_link_fetcher.dart). The change size of a
/// GitLab merge request (+/− lines, files) comes only when the adapter already reports it.
struct MergeRequestLinkFetcher: MergeRequestLinkService {
    let workspaces: WorkspaceRepository
    let tickets: TicketRepository
    let credentials: CredentialStore
    let sync: AccountSyncService

    func fetchMergeRequest(_ link: MergeRequestLink) async -> Outcome<Ticket> {
        guard link.provider == .gitlab || link.provider == .github else { return .failure(.unexpected("Only GitLab and GitHub links")) }
        let accounts = await currentAccounts(workspaces)
        guard let account = accounts.first(where: { $0.providerType == link.provider && Self.host(of: $0) == link.host.lowercased() }),
              account.credentialsRef != nil else {
            return .failure(.notFound("No \(link.provider.rawValue) account for \(link.host)"))
        }
        guard let adapter = await sync.adapter(for: account) else { return .failure(.auth("\(link.provider.rawValue) account is not signed in")) }
        // The adapters read the item from project + number + type; the rest comes from the reply.
        let gitlab = link.provider == .gitlab
        let stub = Ticket(id: "\(account.id):\(link.project):\(link.number)", accountId: account.id, projectId: "\(account.id):\(link.project)",
                          providerType: link.provider, externalKey: link.number, title: "", body: "", priority: .medium, status: .todo,
                          providerStatus: "", sourceHash: "",
                          externalType: link.kind == .issue ? "Issue" : (gitlab ? "MergeRequest" : "PullRequest"))
        switch await adapter.getTicket(stub) {
        case .failure(let f): return .failure(f)
        case .success(let ticket):
            _ = await tickets.upsertTickets([ticket])
            return .success(ticket)
        }
    }

    /// The host an account's links use; GitHub accounts without a base URL are github.com.
    static func host(of account: Account) -> String {
        let base = (account.baseUrl ?? "").trimmingCharacters(in: .whitespaces)
        if base.isEmpty { return account.providerType == .github ? "github.com" : "" }
        let host = URL(string: base.contains("://") ? base : "https://\(base)")?.host?.lowercased() ?? ""
        return host == "api.github.com" ? "github.com" : host
    }
}

/// Late-bound "show this chat" call for `ChatServices.showChat`.
final class ShowChatRelay: @unchecked Sendable {
    var handler: (@Sendable (String, String) -> Void)?
    func call(_ accountId: String, _ gid: String) { handler?(accountId, gid) }
}
