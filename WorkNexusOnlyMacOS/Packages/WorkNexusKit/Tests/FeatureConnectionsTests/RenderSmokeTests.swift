import AppKit
import CoreDomain
import CoreUI
import SwiftUI
import XCTest
@testable import FeatureConnections

/// Renders the connections views off-screen (PNGs in /tmp/wn-feat-render/connections-*.png) so layout problems
/// show up; asserts only that something non-blank was drawn.
@MainActor
final class RenderSmokeTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/wn-feat-render")

    private func render<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var settings = AppSettings(); if dark { settings.variant = .dark }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.padding(24).frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(theme.colors.bg).environment(\.appTheme, theme).environment(\.colorScheme, theme.colorScheme))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: outDir.appendingPathComponent("connections-\(name).png"))
        XCTAssertGreaterThan(png.count, 2_000, "\(name) rendered blank")
    }

    private func model(workspaces: [Workspace]? = nil) async throws -> ConnectionsModel {
        let ws = workspaces ?? [Workspace(id: "w1", name: "Company A", shortCode: "CA", colorValue: 0xFF3B82F6),
                                Workspace(id: "w2", name: "Company B", shortCode: "CB", colorValue: 0xFF16A99C)]
        let accounts = [
            Account(id: "zt-jun-1", workspaceId: "w1", providerType: .zentao, handle: "jun.ng", baseUrl: "https://zentao.example.com/zentao/", credentialsRef: "secret:zt-jun-1"),
            Account(id: "gl-jun-1", workspaceId: "w1", providerType: .gitlab, handle: "jun", baseUrl: "https://gitlab.com", credentialsRef: "secret:gl-jun-1"),
            Account(id: "gh-jun-1", workspaceId: "w1", providerType: .github, handle: "jun-dev", baseUrl: "https://github.com", credentialsRef: "secret:gh-jun-1"),
            Account(id: "demo", workspaceId: "w1", providerType: .zentao, handle: "demo", baseUrl: nil)]
        let m = ConnectionsModel(workspaces: FakeWorkspaces(workspaces: ws, accounts: accounts), tickets: FakeTickets(), credentials: FakeCredentials(),
                                 sync: FakeSync(), adapters: NoAdapters(), connections: RecordingConnections(), cache: RecordingCache())
        m.start()
        try await Task.sleep(for: .milliseconds(80))
        return m
    }

    func testIntegrationsPage() async throws {
        let m = try await model()
        try render("integrations", IntegrationsContentView(model: m, workspaceId: "w1"), size: CGSize(width: 860, height: 640))
        try render("integrations-dark", IntegrationsContentView(model: m, workspaceId: "w1"), size: CGSize(width: 860, height: 640), dark: true)
    }

    func testConnectDialogs() async throws {
        let m = try await model()
        let wsOne = try await model(workspaces: [Workspace(id: "w1", name: "Company A", shortCode: "CA", colorValue: 0xFF3B82F6)])
        try render("connect-zentao", ConnectAccountDialog(model: wsOne, onClose: {}, onSyncWarning: { _ in }), size: CGSize(width: 560, height: 640))
        try render("connect-several-workspaces", ConnectAccountDialog(model: m, onClose: {}, onSyncWarning: { _ in }), size: CGSize(width: 560, height: 640), dark: true)
    }

    func testWorkspaceEditorAndCachePanel() async throws {
        let m = try await model()
        try render("workspace-editor", WorkspaceEditorDialog(workspace: m.workspaces[0], onSave: { _ in }, onClose: {}), size: CGSize(width: 560, height: 520))
        try render("cache-panel", LocalCachePanelView(model: m, onCleared: { _ in }), size: CGSize(width: 640, height: 460))
    }

    func testErrorNote() throws {
        try render("error-note", ConnectionErrorNote(message: "Couldn't reach the server"), size: CGSize(width: 420, height: 100))
    }
}
