import AppKit
import CoreDomain
import CoreUI
import SwiftUI
import XCTest
@testable import FeatureNotifications

/// Renders the notifications panel off-screen (PNGs in /tmp/wn-feat-render) so layout crashes show up in tests and the
/// result can be eyeballed. Asserts only that something non-blank was drawn.
@MainActor
final class RenderSmokeTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/wn-feat-render")

    private func render<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var settings = AppSettings(); if dark { settings.variant = .dark }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.environment(\.appTheme, theme).frame(width: size.width, height: size.height)
            .background(theme.colors.bg).environment(\.colorScheme, theme.colorScheme))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: outDir.appendingPathComponent("\(name).png"))
        XCTAssertGreaterThan(png.count, 2_000, "\(name) rendered blank")
    }

    private final class Repo: ZenTaoNotificationRepository, @unchecked Sendable {
        let items: [ZenTaoNotification]
        init(_ items: [ZenTaoNotification]) { self.items = items }
        func watchAll() -> AsyncStream<[ZenTaoNotification]> { AsyncStream { $0.yield(items) } }
        func refresh(accountId: String) async -> Outcome<Void> { .success(()) }
        func markRead(accountId: String, id: String?) async -> Outcome<Void> { .success(()) }
        func markUnread(accountId: String, id: String) async -> Outcome<Void> { .success(()) }
        func delete(accountId: String, id: String) async -> Outcome<Void> { .success(()) }
        func deleteRead(accountId: String) async -> Outcome<Void> { .success(()) }
    }

    private final class Workspaces: WorkspaceRepository, @unchecked Sendable {
        func watchAccounts() -> AsyncStream<[Account]> {
            AsyncStream { $0.yield([Account(id: "zt", workspaceId: "w", providerType: .zentao, handle: "me")]) }
        }
        func watchWorkspaces() -> AsyncStream<[Workspace]> { AsyncStream { _ in } }
        func watchProjects() -> AsyncStream<[Project]> { AsyncStream { _ in } }
        func createWorkspace(_ workspace: Workspace) async -> Outcome<Void> { .success(()) }
        func updateWorkspace(_ workspace: Workspace) async -> Outcome<Void> { .success(()) }
        func upsertAccount(_ account: Account) async -> Outcome<Void> { .success(()) }
        func deleteAccount(id: String) async -> Outcome<Void> { .success(()) }
        func upsertProjects(_ projects: [Project]) async -> Outcome<Void> { .success(()) }
    }

    private func model(_ items: [ZenTaoNotification]) -> NotificationsModel {
        let m = NotificationsModel(repository: Repo(items), workspaces: Workspaces(), hooks: NotificationsHooks(openTicket: { _ in }),
                                   poller: NotificationPoller(interval: .seconds(3600)))
        m.start(); m.openPanel()
        return m
    }

    private func sample() -> [ZenTaoNotification] {
        let now = Date()
        func n(_ id: String, _ summary: String, _ type: String, _ title: String, ago: TimeInterval, read: Bool = false) -> ZenTaoNotification {
            ZenTaoNotification(accountId: "zt", id: id, summary: summary, objectType: type, objectId: "64\(id)", objectTitle: title,
                               url: "https://zt.example.com/\(type)-view-64\(id).html", read: read, createdAt: now.addingTimeInterval(-ago))
        }
        return [n("1", "JunNg-VN-Flutter assigned Bug", "bug", "[Discover] Feed: Video autoplay is delayed after fast scrolling", ago: 300),
                n("2", "Thanh-VN-Flutter指派了Task", "task", "Implement the notification panel slide-over", ago: 3600),
                n("3", "Luci finished Task", "task", "Port the board filters", ago: 7200, read: true),
                n("4", "Ryan commented Story", "story", "Offline mode for the chat", ago: 90_000),
                n("5", "Cat resolved Bug", "bug", "Crash on launch with an empty workspace", ago: 200_000)]
    }

    func testPanelUnreadAndAll() async throws {
        let m = model(sample())
        try await Task.sleep(for: .milliseconds(200))
        try render("notifications-unread", NotificationsPanel(model: m), size: CGSize(width: 520, height: 640))
        m.unreadOnly = false
        try render("notifications-all-dark", NotificationsPanel(model: m), size: CGSize(width: 520, height: 640), dark: true)
        m.stop()
    }

    func testEmptyPanelAndBell() async throws {
        let m = model([])
        try await Task.sleep(for: .milliseconds(200))
        try render("notifications-empty", NotificationsPanel(model: m), size: CGSize(width: 520, height: 420))
        let m2 = model(sample())
        try await Task.sleep(for: .milliseconds(200))
        try render("notifications-bell", NotificationsBellButton(model: m2).padding(), size: CGSize(width: 120, height: 100))
        m.stop(); m2.stop()
    }
}
