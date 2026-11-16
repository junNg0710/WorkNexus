import AppKit
import CoreDomain
import SwiftUI
import XCTest
@testable import CoreUI

/// Renders the new CoreUI widgets (video player, editor toolbar and colour palette, drop hint, coming soon, storage
/// panel) off-screen to `/tmp/wn-zt2-render/*.png`, for looking at.
@MainActor
final class VideoEditorRenderTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/wn-zt2-render")

    private func render<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false, wait: Double = 0.7) async throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var settings = AppSettings(); if dark { settings.variant = .dark }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.environment(\.appTheme, theme).frame(width: size.width, height: size.height)
            .background(theme.colors.panel).environment(\.colorScheme, theme.colorScheme))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(Int(wait * 1000)))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: outDir.appendingPathComponent("\(name).png"))
        XCTAssertGreaterThan(png.count, 1_500, "\(name) rendered blank")
    }

    func testThePlayerPlayingPausedAndInItsStates() async throws {
        let url = try await TestVideo.make(seconds: 6)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = AppVideoSource(title: "repro.mp4", fileExtension: "mp4", sizeBytes: 90_000, download: { url.path })
        try await render("video-player", AppVideoPlayerView(source: source), size: CGSize(width: 760, height: 480), wait: 1.5)
        try await render("video-player-dark", AppVideoPlayerView(source: source), size: CGSize(width: 760, height: 480), dark: true, wait: 1.5)
        try await render("video-player-narrow", AppVideoPlayerView(source: source), size: CGSize(width: 400, height: 320), wait: 1.5)
        let webm = AppVideoSource(title: "repro.webm", fileExtension: "webm", download: { nil })
        try await render("video-external", AppVideoPlayerView(source: webm), size: CGSize(width: 520, height: 300))
        let broken = AppVideoSource(title: "x.mp4", fileExtension: "mp4", download: { nil })
        try await render("video-failed", AppVideoPlayerView(source: broken), size: CGSize(width: 520, height: 300))
    }

    func testTheVideoFrameCardWithAndWithoutAStill() async throws {
        let still = NSImage(size: NSSize(width: 320, height: 180), flipped: false) { rect in
            NSColor.systemTeal.setFill(); rect.fill(); return true
        }
        let png = NSBitmapImageRep(data: still.tiffRepresentation!)!.representation(using: .png, properties: [:])
        try await render("video-frame-cards", VStack(alignment: .leading, spacing: 12) {
            VideoFrameCard(title: "repro-steps.mp4", size: 8_400_000, loadStill: { png }, onTap: {})
            VideoFrameCard(title: "no-still.mov", size: nil, onTap: {})
        }.padding(16), size: CGSize(width: 440, height: 360))
    }

    func testTheEditorToolbarWithItsColourButtons() async throws {
        let controller = HtmlEditingController(html: "<p>Some <span style=\"color:#e03e2d\">coloured</span> text</p>")
        try await render("editor-toolbar", RichTextEditor(controller: controller, onUploadImage: { _, _ in nil }, onDropFiles: { _ in }, minHeight: 120)
            .padding(12), size: CGSize(width: 640, height: 240))
        try await render("editor-toolbar-dark", RichTextEditor(controller: controller, onUploadImage: { _, _ in nil }, minHeight: 120)
            .padding(12), size: CGSize(width: 640, height: 240), dark: true)
    }

    func testTheColourPaletteAndItsDefaultRow() async throws {
        try await render("editor-palette", EditorColorPalette(current: "#e03e2d", onPick: { _ in }, onCustom: {}), size: CGSize(width: 260, height: 260))
        try await render("editor-palette-none", EditorColorPalette(current: nil, onPick: { _ in }, onCustom: {}), size: CGSize(width: 260, height: 260), dark: true)
    }

    func testTheDropHintComingSoonAndStoragePanel() async throws {
        try await render("drop-hint", FileDropOverlay(hint: "Drop images to insert, other files to attach", active: true).padding(20), size: CGSize(width: 480, height: 160))
        try await render("coming-soon", ComingSoonView(systemImage: "play", title: "Pipelines", message: "Coming soon.", actionLabel: "Back", onAction: {}), size: CGSize(width: 480, height: 280))
        try await render("storage-panel", AttachmentStoragePanel(usage: { .success(23_500_000) }, clear: { .success(()) }).padding(20), size: CGSize(width: 440, height: 200))
    }
}

/// The view hosts a model the caller owns: once started it is ready, playing, and its picture is in the view tree.
@MainActor
final class VideoPlayerViewTests: XCTestCase {
    private func surfaces(_ v: NSView, _ out: inout [PlayerLayerView]) {
        if let p = v as? PlayerLayerView { out.append(p) }
        v.subviews.forEach { surfaces($0, &out) }
    }

    func testAHostedModelPlaysAndItsPictureIsInTheTree() async throws {
        let url = try await TestVideo.make(seconds: 4)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = AppVideoPlayerModel(source: AppVideoSource(title: "repro.mp4", fileExtension: "mp4", download: { url.path }))
        let host = NSHostingView(rootView: AppVideoPlayerView(model: model).environment(\.appTheme, AppTheme()).frame(width: 640, height: 400))
        host.frame = CGRect(x: 0, y: 0, width: 640, height: 400)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        try await Task.sleep(for: .seconds(3))
        host.layoutSubtreeIfNeeded()
        var found: [PlayerLayerView] = []
        surfaces(host, &found)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.playerLayer.player === model.player, true)
        XCTAssertEqual(model.duration, 4, accuracy: 0.3)
        model.stop()
    }
}
