import AppKit
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI
import XCTest
@testable import SharedKit

/// Renders the shell's new views off-screen (`/tmp/wn-shell-render/*.png`) so layout crashes show up in `swift test` and the
/// PNGs can be eyeballed. Asserts only that something non-blank was drawn.
@MainActor
final class ShellRenderTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/wn-shell-render")

    private func render<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var settings = AppSettings(); if dark { settings.variant = .dark; settings.themeFollowsSystem = false }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.environment(\.appTheme, theme).frame(width: size.width, height: size.height)
            .background(theme.colors.bg).environment(\.colorScheme, theme.colorScheme))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: outDir.appendingPathComponent("\(name).png"))
        XCTAssertGreaterThan(png.count, 1_500, "\(name) rendered blank")
    }

    private func shell() async -> ShellModel {
        let a = Workspace(id: "a", name: "Acme Corporation", shortCode: "AC", colorValue: 0xFF3B82F6)
        let b = Workspace(id: "b", name: "Personal", shortCode: "PE", colorValue: 0xFF16A99C, isPersonal: true)
        let live = LiveWorkspaces([a, b], [Account(id: "zt", workspaceId: "a", providerType: .zentao, handle: "thanh"),
                                           Account(id: "gl", workspaceId: "a", providerType: .gitlab, handle: "thanh")])
        let fake = FakeStore()
        let services = AppServices(tickets: fake, workspaces: live, comments: fake, activity: fake, syncStatus: SyncTests.RecordingStatus(),
                                   settings: BoardControllerTests.FakeSettings(), credentials: fake, sync: BoardControllerTests.NoopSync(),
                                   ticketDetail: BoardControllerTests.NoopSync(), adapters: FakeRegistry())
        let m = ShellModel(services: services, registry: ToolRegistry())
        m.opensChatAtLaunch = false
        m.start()
        for _ in 0..<100 where !(m.loadedAccounts && m.loadedWorkspaces) { try? await Task.sleep(for: .milliseconds(10)) }
        return m
    }

    func testSwitcherPopover() async throws {
        let m = await shell()
        try render("switcher", WorkspaceSwitcherPopover(model: m) {}, size: CGSize(width: 324, height: 384))
        try render("switcher-dark", WorkspaceSwitcherPopover(model: m) {}, size: CGSize(width: 324, height: 384), dark: true)
        try render("breadcrumb", WorkspaceBreadcrumb(model: m).padding(), size: CGSize(width: 520, height: 52))
    }

    func testBannersAndErrorBoundary() async throws {
        let m = await shell()
        let acct = Account(id: "zt", workspaceId: "a", providerType: .zentao, handle: "thanh")
        try render("banner-auth", AccountBanners(model: m, account: acct, health: .authExpired), size: CGSize(width: 900, height: 56))
        try render("banner-offline", AccountBanners(model: m, account: acct, health: .offline(blocked: false)), size: CGSize(width: 900, height: 56))
        try render("banner-failed", AccountBanners(model: m, account: acct, health: .failed("HTTP 500", blocked: false)), size: CGSize(width: 900, height: 56), dark: true)
        try render("section-error", SectionErrorBoundary(message: "Couldn't sync thanh: HTTP 500") {}, size: CGSize(width: 500, height: 260))
    }

    func testAppShellAndFireworks() async throws {
        let m = await shell()
        try render("shell", AppShell(model: m), size: CGSize(width: 1100, height: 700))
        m.celebrate()
        try render("celebration", CelebrationOverlay(controller: m.celebration), size: CGSize(width: 900, height: 600), dark: true)
    }
}
