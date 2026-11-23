import CoreDomain
import CoreUI
import XCTest
@testable import FeatureNotifications

private actor Calls {
    var items: [String] = []
    func add(_ s: String) { items.append(s) }
}

private final class FakeRepo: ZenTaoNotificationRepository, @unchecked Sendable {
    let calls = Calls()
    var failRefresh: Failure?
    var failCommands = false
    private var cont: AsyncStream<[ZenTaoNotification]>.Continuation?
    private var names: AsyncStream<[String: String]>.Continuation?
    func watchAll() -> AsyncStream<[ZenTaoNotification]> { AsyncStream { cont = $0 } }
    func watchAccountRealnames() -> AsyncStream<[String: String]> { AsyncStream { names = $0 } }
    func emit(_ list: [ZenTaoNotification]) { cont?.yield(list) }
    func emitNames(_ n: [String: String]) { names?.yield(n) }
    func refresh(accountId: String) async -> Outcome<Void> {
        await calls.add("refresh:\(accountId)")
        return failRefresh.map { .failure($0) } ?? .success(())
    }
    private func cmd(_ s: String) async -> Outcome<Void> {
        await calls.add(s)
        return failCommands ? .failure(.network("x")) : .success(())
    }
    func markRead(accountId: String, id: String?) async -> Outcome<Void> { await cmd("read:\(accountId):\(id ?? "all")") }
    func markUnread(accountId: String, id: String) async -> Outcome<Void> { await cmd("unread:\(accountId):\(id)") }
    func delete(accountId: String, id: String) async -> Outcome<Void> { await cmd("delete:\(accountId):\(id)") }
    func deleteRead(accountId: String) async -> Outcome<Void> { await cmd("deleteRead:\(accountId)") }
}

private final class FakeWorkspaces: WorkspaceRepository, @unchecked Sendable {
    private var cont: AsyncStream<[Account]>.Continuation?
    func emit(_ a: [Account]) { cont?.yield(a) }
    func watchAccounts() -> AsyncStream<[Account]> { AsyncStream { cont = $0 } }
    func watchWorkspaces() -> AsyncStream<[Workspace]> { AsyncStream { _ in } }
    func watchProjects() -> AsyncStream<[Project]> { AsyncStream { _ in } }
    func createWorkspace(_ workspace: Workspace) async -> Outcome<Void> { .success(()) }
    func updateWorkspace(_ workspace: Workspace) async -> Outcome<Void> { .success(()) }
    func upsertAccount(_ account: Account) async -> Outcome<Void> { .success(()) }
    func deleteAccount(id: String) async -> Outcome<Void> { .success(()) }
    func upsertProjects(_ projects: [Project]) async -> Outcome<Void> { .success(()) }
}

private final class FakeNotifier: DesktopNotifying, @unchecked Sendable {
    let shown = Calls()
    var taps: AsyncStream<String> { AsyncStream { _ in } }
    func initialize() async -> Bool { true }
    func permissionGranted() async -> Bool? { true }
    func requestPermission() async -> Bool { true }
    func openSystemSettings() {}
    func show(id: Int, title: String, body: String, payload: String?) async { await shown.add("\(title)|\(body)|\(payload ?? "")") }
}

@MainActor private final class FakeBadge: DockBadging { var last = -1; func show(_ count: Int) { last = count } }

@MainActor
final class NotificationsModelTests: XCTestCase {
    private let account = Account(id: "zt", workspaceId: "w", providerType: .zentao, handle: "me")
    private func n(_ id: String, _ summary: String = "Other assigned Bug", read: Bool = false, type: String? = "bug",
                   url: String? = "https://zt.example.com/bug-view-1.html") -> ZenTaoNotification {
        ZenTaoNotification(accountId: "zt", id: id, summary: summary, objectType: type, objectId: "1", objectTitle: "Crash",
                           url: url, read: read, createdAt: Date())
    }

    private struct Harness {
        let model: NotificationsModel; let repo: FakeRepo; let ws: FakeWorkspaces; let notifier: FakeNotifier
        let badge: FakeBadge; let opened: Calls; let toasts: Calls
    }

    private func make(resolve: Bool = true, focused: Bool = false) -> Harness {
        let repo = FakeRepo(), ws = FakeWorkspaces(), notifier = FakeNotifier(), badge = FakeBadge()
        let opened = Calls(), toasts = Calls()
        let hooks = NotificationsHooks(openTicket: { id in Task { await opened.add("ticket:\(id)") } },
                                       openURL: { url in Task { await opened.add("url:\(url)") }; return true },
                                       toast: { msg, _ in Task { await toasts.add(msg) } },
                                       isAppFocused: { focused }, bringToFront: {})
        let model = NotificationsModel(
            repository: repo, workspaces: ws,
            resolveTicket: resolve ? { _, type, id in .success("zt:\(type):\(id)") } : nil,
            notifier: notifier, dockBadge: badge, hooks: hooks,
            poller: NotificationPoller(interval: .seconds(3600)))
        return Harness(model: model, repo: repo, ws: ws, notifier: notifier, badge: badge, opened: opened, toasts: toasts)
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(120)) }

    func testRefreshesOnceWhenAnAccountAppearsAndShowsStoredList() async {
        let h = make(); h.model.start(); await settle()
        h.ws.emit([account, Account(id: "gh", workspaceId: "w", providerType: .github, handle: "x")]); await settle()
        h.repo.emit([n("1"), n("2", read: true)]); await settle()
        let calls = await h.repo.calls.items
        XCTAssertEqual(calls, ["refresh:zt"])
        XCTAssertEqual(h.model.accounts.map(\.id), ["zt"])
        XCTAssertEqual(h.model.notifications.count, 2)
        XCTAssertEqual(h.model.unreadCount, 1)
        XCTAssertEqual(h.badge.last, 1)
        XCTAssertEqual(h.model.days.flatMap(\.items).map(\.id), ["1"], "unread tab by default")
        h.model.stop()
    }

    func testTheNewestUnreadNotificationIsWhatThePetSays() async {
        let h = make(); h.model.start(); await settle()
        h.ws.emit([account]); await settle()
        XCTAssertNil(h.model.newestUnreadText)
        let old = Date(timeIntervalSince1970: 1_000), new = Date(timeIntervalSince1970: 2_000)
        h.repo.emit([
            ZenTaoNotification(accountId: "zt", id: "1", summary: "Other assigned Bug", objectType: "bug", objectId: "6", objectTitle: "Old", createdAt: old),
            ZenTaoNotification(accountId: "zt", id: "2", summary: "Other assigned Bug", objectType: "bug", objectId: "7", objectTitle: "Login fails", createdAt: new),
            ZenTaoNotification(accountId: "zt", id: "3", summary: "Other assigned Bug", objectType: "bug", objectId: "8", objectTitle: "Read",
                               read: true, createdAt: new.addingTimeInterval(60)),
        ]); await settle()
        let text = try? XCTUnwrap(h.model.newestUnreadText)
        XCTAssertTrue(text?.hasSuffix("#7 Login fails") == true, text ?? "nil")
        h.model.stop()
    }

    func testOwnActionsAreHiddenByRealname() async {
        let h = make(); h.model.start(); await settle()
        h.ws.emit([account]); await settle()
        h.repo.emitNames(["zt": "Me Myself"]); await settle()
        h.repo.emit([n("1", "Me Myself started Task"), n("2", "me closed Bug"), n("3")]); await settle()
        XCTAssertEqual(h.model.notifications.map(\.id), ["3"])
        h.model.stop()
    }

    func testFailedRefreshIsAStateNotAThrow() async {
        let h = make(); h.repo.failRefresh = .auth("expired"); h.model.start(); await settle()
        h.ws.emit([account]); await settle()
        XCTAssertEqual(h.model.refreshState, .failed("expired"))
        h.repo.failRefresh = nil
        await h.model.refresh()
        XCTAssertEqual(h.model.refreshState, .idle)
        h.model.stop()
    }

    func testDesktopAlertsSkipBacklogAndRaiseNewOnes() async {
        let h = make(); h.model.start(); await settle()
        h.ws.emit([account]); h.repo.emit([n("1")]); await settle()
        var shown = await h.notifier.shown.items
        XCTAssertTrue(shown.isEmpty, "the first list is the backlog")
        h.repo.emit([n("1"), n("2", "Other commented Task", type: "task")]); await settle()
        shown = await h.notifier.shown.items
        XCTAssertEqual(shown.count, 1)
        XCTAssertTrue(shown[0].hasPrefix("Other commented on Task|#1 Crash|"), shown[0])
        XCTAssertTrue(shown[0].contains("\"zn\":\"2\""))
        h.model.stop()
    }

    func testNoAlertWhileLookingAtThePanel() async {
        let h = make(focused: true); h.model.start(); await settle()
        h.ws.emit([account]); h.repo.emit([n("1")]); await settle()
        h.model.openPanel()
        h.repo.emit([n("1"), n("2")]); await settle()
        let shown = await h.notifier.shown.items
        XCTAssertTrue(shown.isEmpty)
        h.model.stop()
    }

    func testOpeningATicketResolvesItAndMarksReadOptimistically() async {
        let h = make()
        await h.model.open(n("5"))
        await settle()
        let opened = await h.opened.items, calls = await h.repo.calls.items
        XCTAssertEqual(opened, ["ticket:zt:bug:1"])
        XCTAssertEqual(calls, ["read:zt:5"])
    }

    func testNonTicketOpensInBrowserAndFailureToasts() async {
        let h = make()
        await h.model.open(n("6", read: true, type: "doc", url: "https://zt.example.com/doc-view-9.html")); await settle()
        var opened = await h.opened.items
        XCTAssertEqual(opened, ["url:https://zt.example.com/doc-view-9.html"])
        await h.model.open(n("7", read: true, type: "doc", url: nil)); await settle()
        opened = await h.opened.items
        let toasts = await h.toasts.items
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(toasts, ["Couldn't open this item"])
    }

    func testCommandFailureToasts() async {
        let h = make(); h.repo.failCommands = true
        await h.model.delete(n("1")); await settle()
        let toasts = await h.toasts.items
        XCTAssertEqual(toasts, ["Couldn't update the notification on ZenTao"])
    }

    func testMarkAllAndDeleteReadRunPerAccount() async {
        let h = make(); h.model.start(); await settle()
        h.ws.emit([account]); await settle()
        await h.model.markAllRead(); await h.model.deleteRead()
        let calls = await h.repo.calls.items
        XCTAssertEqual(calls, ["refresh:zt", "read:zt:all", "deleteRead:zt"])
        h.model.stop()
    }

    func testTapOpensTheNotificationOrTheList() async {
        let h = make(); h.model.start(); await settle()
        h.ws.emit([account]); h.repo.emit([n("9")]); await settle()
        await h.model.handleTap(payload: NotificationAlertPayload(notificationId: "9", accountId: "zt").json)
        await settle()
        var opened = await h.opened.items
        XCTAssertEqual(opened, ["ticket:zt:bug:1"])
        await h.model.handleTap(payload: NotificationAlertPayload(notificationId: nil).json)
        XCTAssertTrue(h.model.panelOpen)
        await h.model.handleTap(payload: "garbage")
        opened = await h.opened.items
        XCTAssertEqual(opened.count, 1)
        h.model.stop()
    }

    func testPollerTicksUntilStopped() async {
        let count = Calls()
        let poller = NotificationPoller(interval: .milliseconds(10))
        poller.start { await count.add("t") }
        poller.start { await count.add("second") }   // idempotent
        try? await Task.sleep(for: .milliseconds(120))
        poller.stop()
        let n1 = await count.items
        XCTAssertGreaterThan(n1.count, 2)
        XCTAssertFalse(n1.contains("second"))
        try? await Task.sleep(for: .milliseconds(60))
        let n2 = await count.items
        XCTAssertEqual(n1.count, n2.count)
        XCTAssertEqual(NotificationPoller.defaultInterval, .seconds(120))
    }

    /// Without a network the poll waits: nothing is asked until it is back.
    func testPollerSkipsTicksWhileOffline() async {
        let count = Calls()
        let online = OnlineFlag()
        let poller = NotificationPoller(interval: .milliseconds(10), isOnline: { online.value })
        poller.start { await count.add("t") }
        try? await Task.sleep(for: .milliseconds(100))
        let whileOffline = await count.items
        XCTAssertTrue(whileOffline.isEmpty)
        online.value = true
        try? await Task.sleep(for: .milliseconds(150))
        poller.stop()
        let after = await count.items
        XCTAssertFalse(after.isEmpty)
    }
}

/// Whether the Mac has a network, as a test sets it.
private final class OnlineFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var online = false
    var value: Bool {
        get { lock.withLock { online } }
        set { lock.withLock { online = newValue } }
    }
}
