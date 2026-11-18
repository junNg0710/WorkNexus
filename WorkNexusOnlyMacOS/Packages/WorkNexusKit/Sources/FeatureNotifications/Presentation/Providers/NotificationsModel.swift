import CoreDomain
import CoreUI
import Foundation
import Observation

/// Ported from: lib/features/notifications/presentation/providers/notification_providers.dart (+ notification_actions,
/// notification_alerts). The one observable the panel, the rail bell and the desktop alerts share. Local-first:
/// the list is the stored one (`watchAll`), polled from ZenTao every two minutes; commands change the store first.
@MainActor @Observable
public final class NotificationsModel {
    /// Fetch state of the notifications of every ZenTao account: loading while a refresh runs, failed when the last
    /// one did.
    public enum RefreshState: Equatable, Sendable { case idle, loading, failed(String) }

    /// Stored notifications of every ZenTao account, newest first, without the user's own actions.
    public private(set) var notifications: [ZenTaoNotification] = []
    /// Connected ZenTao accounts: notifications exist per account.
    public private(set) var accounts: [Account] = []
    public private(set) var refreshState: RefreshState = .idle
    /// True once the stored list has been read (before that the panel shows a spinner).
    public private(set) var hasLoaded = false
    /// The panel's tab: true = unread only (ZenTao's default), false = all.
    public var unreadOnly = true
    public private(set) var panelOpen = false

    @ObservationIgnored private let repository: ZenTaoNotificationRepository
    @ObservationIgnored private let workspaces: WorkspaceRepository
    @ObservationIgnored private let resolveTicket: (@Sendable (_ host: String, _ type: String, _ id: String) async -> Outcome<String>)?
    @ObservationIgnored private let notifier: DesktopNotifying?
    @ObservationIgnored private let dockBadge: DockBadging?
    @ObservationIgnored private let hooks: NotificationsHooks
    @ObservationIgnored private let poller: NotificationPoller
    @ObservationIgnored private var all: [ZenTaoNotification] = []
    @ObservationIgnored private var realnames: [String: String] = [:]
    @ObservationIgnored private var seen: Set<String>?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    public init(repository: ZenTaoNotificationRepository, workspaces: WorkspaceRepository,
                resolveTicket: (@Sendable (_ host: String, _ type: String, _ id: String) async -> Outcome<String>)? = nil,
                notifier: DesktopNotifying? = nil, dockBadge: DockBadging? = nil, hooks: NotificationsHooks,
                poller: NotificationPoller = NotificationPoller()) {
        self.repository = repository; self.workspaces = workspaces; self.resolveTicket = resolveTicket
        self.notifier = notifier; self.dockBadge = dockBadge; self.hooks = hooks; self.poller = poller
    }

    // MARK: Derived

    public var unreadCount: Int { notifications.filter { !$0.read }.count }
    /// What the newest unread notification says, as its desktop alert does: "JunNg assigned Bug · #6492 Feed: video...".
    public var newestUnreadText: String? {
        let unread = notifications.filter { !$0.read }
        guard let n = unread.max(by: { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }) ?? unread.first else { return nil }
        let object = [n.objectId.map { "#\($0)" }, n.objectTitle].compactMap { $0 }.joined(separator: " ")
        return object.isEmpty ? NotificationStrings.eventText(n) : "\(NotificationStrings.eventText(n)) · \(object)"
    }
    /// The notifications shown on the panel, grouped by day.
    public var days: [NotificationDay] { GroupNotificationsByDay()(notifications, unreadOnly: unreadOnly) }
    public var isRefreshing: Bool { refreshState == .loading }
    public var refreshFailed: Bool { if case .failed = refreshState { true } else { false } }

    // MARK: Lifecycle

    /// Starts watching the store and the accounts, and polling ZenTao. Idempotent.
    public func start() {
        guard tasks.isEmpty else { return }
        tasks = [
            Task { [weak self] in
                guard let stream = self?.workspaces.watchAccounts() else { return }
                for await accounts in stream { await self?.onAccounts(accounts) }
            },
            Task { [weak self] in
                guard let stream = self?.repository.watchAccountRealnames() else { return }
                for await names in stream { await self?.onRealnames(names) }
            },
            Task { [weak self] in
                guard let stream = self?.repository.watchAll() else { return }
                for await list in stream { await self?.onStored(list) }
            },
        ]
        if let notifier {
            tasks.append(Task { [weak self] in
                for await payload in notifier.taps { await self?.handleTap(payload: payload) }
            })
        }
        poller.start { [weak self] in await self?.refresh() }
    }

    public func stop() {
        tasks.forEach { $0.cancel() }; tasks = []
        poller.stop()
    }

    // MARK: Stream input

    private func onAccounts(_ list: [Account]) {
        let zentao = list.filter { $0.providerType == .zentao }
        let changed = Set(zentao.map(\.id)) != Set(accounts.map(\.id))
        accounts = zentao
        recompute()
        // Watching the accounts fetches once, as soon as there is one to fetch for.
        if changed, !zentao.isEmpty { Task { await refresh() } }
    }

    private func onRealnames(_ names: [String: String]) { realnames = names; recompute() }

    private func onStored(_ list: [ZenTaoNotification]) { all = list; hasLoaded = true; recompute() }

    private func recompute() {
        let filtered = FilterSelfNotifications()(all, accounts: accounts, realnamesByAccountId: realnames)
        guard filtered != notifications || !hasLoaded else { return }
        notifications = filtered
        dockBadge?.show(unreadCount)
        Task { await raiseAlerts(for: filtered) }
    }

    // MARK: Refresh

    /// Fetches the notifications of every ZenTao account now (a refresh already running is not repeated).
    public func refresh() async {
        guard !isRefreshing else { return }
        let ids = accounts.map(\.id)
        if ids.isEmpty { return }
        refreshState = .loading
        switch await RefreshNotifications(repository)(ids) {
        case .success: refreshState = .idle
        case .failure(let f): refreshState = .failed(f.message)
        }
    }

    // MARK: Panel

    public func togglePanel() { panelOpen.toggle() }
    public func openPanel() { panelOpen = true }
    public func closePanel() { panelOpen = false }

    // MARK: Commands (optimistic: the store changes first; a failure shows a toast)

    private func run(_ command: @Sendable (ZenTaoNotificationRepository) async -> Outcome<Void>) async {
        if case .failure = await command(repository) { hooks.toast(NotificationStrings.actionFailed, .error) }
    }

    public func markRead(_ n: ZenTaoNotification) async { await run { await $0.markRead(accountId: n.accountId, id: n.id) } }
    public func markUnread(_ n: ZenTaoNotification) async { await run { await $0.markUnread(accountId: n.accountId, id: n.id) } }
    public func delete(_ n: ZenTaoNotification) async { await run { await $0.delete(accountId: n.accountId, id: n.id) } }

    public func markAllRead() async {
        for a in accounts { await run { await $0.markRead(accountId: a.id, id: nil) } }
    }

    public func deleteRead() async {
        for a in accounts { await run { await $0.deleteRead(accountId: a.id) } }
    }

    // MARK: Opening

    private static let ticketTypes: Set<String> = ["bug", "task", "story"]

    /// Opens what `n` links to and marks it read. A bug, task or story opens in the detail panel (fetched from ZenTao
    /// when the board has not synced it); anything else opens in the browser.
    public func open(_ n: ZenTaoNotification) async {
        if !n.read { Task { await markRead(n) } }
        if let type = n.objectType, let id = n.objectId, Self.ticketTypes.contains(type), let resolveTicket {
            let host = URL(string: n.url ?? "")?.host ?? ""
            if case .success(let ticketId) = await resolveTicket(host, type, id) {
                hooks.openTicket(ticketId)
                return
            }
        }
        if let url = n.url, url.hasPrefix("http"), hooks.openURL(url) { return }
        hooks.toast(NotificationStrings.openFailed, .error)
    }

    // MARK: Desktop alerts

    /// Raises a desktop notification for each ZenTao notification a refresh brings in, unless the user is looking
    /// at the list itself. More than a few at once are one notification counting them.
    func raiseAlerts(for list: [ZenTaoNotification]) async {
        let found = FindNewNotifications()(seen: seen, current: list)
        seen = found.seen
        guard !found.fresh.isEmpty, let notifier else { return }
        let focused = await hooks.isAppFocused()
        if focused && panelOpen { return }
        switch PlanDesktopAlerts()(found.fresh) {
        case .none: break
        case .count(let count, let first):
            await notifier.show(id: 0x2e40, title: NotificationStrings.newCount(count), body: NotificationStrings.eventText(first),
                                payload: NotificationAlertPayload(notificationId: nil).json)
        case .each(let items):
            for n in items {
                let body = [n.objectId.map { "#\($0)" }, n.objectTitle].compactMap { $0 }.joined(separator: " ")
                await notifier.show(id: Int(truncatingIfNeeded: Self.stableHash(FindNewNotifications.keyOf(n)) & 0x7fffffff),
                                    title: NotificationStrings.eventText(n), body: body,
                                    payload: NotificationAlertPayload(notificationId: n.id, accountId: n.accountId).json)
            }
        }
    }

    /// Process-independent hash (Swift's `hashValue` is seeded per launch), so one notification keeps its id.
    static func stableHash(_ s: String) -> Int {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
        return Int(h & 0x7fffffff)
    }

    /// A notification of ours opens what it links to; the counting one (or one no longer listed) opens the list.
    public func handleTap(payload: String) async {
        guard let p = NotificationAlertPayload(json: payload) else { return }
        hooks.bringToFront()
        if let tapped = notifications.first(where: { $0.id == p.notificationId && $0.accountId == p.accountId }) {
            await open(tapped)
            return
        }
        if !panelOpen { openPanel() }
    }
}
