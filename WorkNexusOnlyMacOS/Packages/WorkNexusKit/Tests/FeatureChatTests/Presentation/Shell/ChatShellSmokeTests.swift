import AppKit
import CoreDomain
import SwiftUI
import XCTest
@testable import FeatureChat

/// Renders the whole shell with fake data to catch layout crashes; writes PNGs when `WN_SHELL_SNAPSHOT` names a folder.
@MainActor
final class ChatShellSmokeTests: XCTestCase {
    func testShellRendersWithChatsAndAnOpenThread() async throws {
        let repo = ShellFakeRepository()
        let users = [ShellMake.user(1, "Me", account: "me", status: "online"), ShellMake.user(2, "Bình Nguyen", role: "pm", status: "away"), ShellMake.user(3, "An", role: "dev")]
        let account = Account(id: "a", workspaceId: "w", providerType: .zentao, handle: "me")
        let events = ChatShellEvents()
        let root = ChatRootView(account: account, events: events).chatServices(ChatServices(chat: repo)).frame(width: 1400, height: 800)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 1400, height: 800)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await ShellMake.expectEventually { repo.conversationsCont != nil && repo.usersCont != nil && repo.statusCont != nil }
        repo.statusCont?.yield(.online(selfUserId: 1))
        repo.usersCont?.yield(users)
        let last = Make.message("m1", chat: "d", sender: 2, content: .text("See you **tomorrow** at [@An](@#3)"), mine: false)
        var direct = ShellMake.chat("d", type: .one2one, peer: 2, at: Make.t0.timeIntervalSince1970, unread: 2); direct.lastMessage = last
        var group = ShellMake.chat("g", name: "Release Team", at: Make.t0.timeIntervalSince1970 - 5000, starred: true); group.lastMessage = last
        group.ownerAccount = "me"; group.createdAt = Make.t0
        repo.conversationsCont?.yield([direct, group, ShellMake.chat("b", type: .bot, name: "Xuanbot", at: 5)])
        try await settle(host)
        try snapshot(host, "list")
        events.open(chatGid: "g")
        try await settle(host)
        try snapshot(host, "thread")
        events.notificationsBlocked = true
        repo.statusCont?.yield(.reconnecting(retryIn: 3, reason: "x"))
        try await settle(host)
        try snapshot(host, "banners")
        repo.statusCont?.yield(.needsTrust(host: "chat.example.com", fingerprint: (0..<32).map { String(format: "%02X", $0) }.joined(separator: ":"),
                                           subject: "/CN=chat.example.com", issuer: "CN=Local CA"))
        try await settle(host)
        try snapshot(host, "trust")
    }

    /// The list folded away (a second click on Chat in the rail; remembered across launches): the chat takes the whole width.
    func testFoldedListLeavesTheChatTheWholeWidth() async throws {
        ChatPanelVisibility.shared.listHidden = true
        defer { ChatPanelVisibility.shared.listHidden = false; UserDefaults.standard.removeObject(forKey: "chat.listHidden") }
        let repo = ShellFakeRepository()
        let account = Account(id: "a", workspaceId: "w", providerType: .zentao, handle: "me")
        let root = ChatRootView(account: account).chatServices(ChatServices(chat: repo)).frame(width: 900, height: 500)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await ShellMake.expectEventually { repo.conversationsCont != nil }
        repo.conversationsCont?.yield([ShellMake.chat("g", name: "Release Team", at: 1)])
        try await settle(host)
        try snapshot(host, "list-hidden-placeholder")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "chat.listHidden"))
    }

    private func settle(_ host: NSView) async throws {
        for _ in 0..<6 { try await Task.sleep(for: .milliseconds(40)); host.layoutSubtreeIfNeeded() }
    }

    private func snapshot(_ view: NSView, _ name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["WN_SHELL_SNAPSHOT"] else { return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
    }
}
