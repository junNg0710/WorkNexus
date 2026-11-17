import AppKit
import AVFoundation
import CoreDomain
import CoreUI
import SwiftUI
import XCTest
@testable import FeatureChat

/// Renders the new chat dialogs and settings blocks with fake data (catches layout crashes) and writes PNGs to
/// `/tmp/wn-chat-render` (or the folder `WN_CHAT_RENDER` names) so they can be looked at.
@MainActor
final class ChatRenderSmokeTests: XCTestCase {
    private final class Repo: StubChatRepository, @unchecked Sendable {
        override func cacheUsage() async -> Outcome<ChatCacheUsage> {
            .success(ChatCacheUsage(totalBytes: 1_650_000_000, limitBytes: 2 * 1024 * 1024 * 1024, chats: [
                ChatCacheChatUsage(accountId: "a", chatGid: "g", bytes: 900_000_000, imageBytes: 120_000_000, videoBytes: 700_000_000, fileBytes: 80_000_000),
                ChatCacheChatUsage(accountId: "a", chatGid: "d", bytes: 420_000_000, imageBytes: 300_000_000, videoBytes: 0, fileBytes: 120_000_000)]))
        }
        override func watchConversations(accountId: String) -> AsyncStream<[ChatConversation]> {
            AsyncStream { $0.yield(RenderData.chats); $0.finish() }
        }
        override func watchUsers(accountId: String) -> AsyncStream<[ChatUser]> { AsyncStream { $0.yield(RenderData.users); $0.finish() } }
    }

    private enum RenderData {
        static let users = [ShellMake.user(1, "Me", account: "me", status: "online"), ShellMake.user(2, "Bình Nguyen", role: "pm", status: "away"), ShellMake.user(3, "An", role: "dev")]
        static var chats: [ChatConversation] {
            var group = ShellMake.chat("g", name: "Release Team", at: Make.t0.timeIntervalSince1970 - 5000, starred: true)
            group.ownerAccount = "me"
            return [ShellMake.chat("d", type: .one2one, peer: 2, at: Make.t0.timeIntervalSince1970), group, ShellMake.chat("p", name: "Platform", at: 4)]
        }
    }

    private final class Wallpapers: WallpaperRepository, @unchecked Sendable {
        func wallpapers() async -> Outcome<[String]> { .success(["/nonexistent/a.jpg"]) }
        func add(bytes: Data, name: String) async -> Outcome<String> { .success("/x") }
        func remove(path: String) async -> Outcome<Void> { .success(()) }
    }

    private func render<V: View>(_ view: V, _ name: String, width: CGFloat = 520, height: CGFloat = 700, settle: Int = 12, dark: Bool = false,
                                 file: StaticString = #filePath, line: UInt = #line) async throws {
        var settings = AppSettings(); if dark { settings.variant = .dark; settings.themeFollowsSystem = false }
        let theme = AppTheme(settings: settings)
        let root = view.environment(\.appTheme, theme).frame(width: width, height: height).background(theme.colors.bg)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<settle { try await Task.sleep(for: .milliseconds(40)); host.layoutSubtreeIfNeeded() }
        let folder = ProcessInfo.processInfo.environment["WN_CHAT_RENDER"] ?? "/tmp/wn-chat-render"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds), file: file, line: line)
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
    }

    private func model(_ repo: Repo) -> ChatShellModel {
        let m = ChatShellModel(accountId: "a", selfAccount: "me", repository: repo)
        m.apply(users: RenderData.users); m.apply(selfUserId: 1); m.apply(conversations: RenderData.chats)
        return m
    }

    func testForwardDialog() async throws {
        let repo = Repo(), m = model(repo)
        let message = Make.message("m1", chat: "g", sender: 2, content: .text("Release notes are **ready**, please review before Friday"), mine: false, serverId: 5)
        try await render(ForwardMessageDialog(model: m, request: ChatForwardRequest(messages: [message])), "forward-dialog", width: 460, height: 720)
        try await render(ForwardMessageDialog(model: m, request: ChatForwardRequest(messages: [message, message, message])), "forward-dialog-many", width: 460, height: 720)
    }

    /// "Multiple select": ticks before the rows (two picked), and the bar that stands in the composer's place.
    func testMultipleSelectRowsAndBar() async throws {
        let m = model(Repo())
        m.events.onCreateTicket = { _ in }
        let state = ChatThreadState(accountId: "a", chat: RenderData.chats[1])
        state.users = Dictionary(uniqueKeysWithValues: RenderData.users.map { ($0.userId, $0) }); state.selfUserId = 1
        let ctx = ThreadContext(model: MessageTimelineModel(state: state, services: ChatServices(chat: Repo())), actions: ChatThreadActions())
        let messages = [
            Make.message("m1", chat: "g", sender: 2, content: .text("Login fails on Safari after the last deploy"), serverId: 5),
            Make.message("m2", chat: "g", sender: 3, at: Make.t0.addingTimeInterval(60), content: .text("Same here, the token is empty"), serverId: 6),
            Make.message("m3", chat: "g", sender: 1, at: Make.t0.addingTimeInterval(120), content: .text("I'll file a bug"), mine: true, serverId: 7),
        ]
        state.beginSelection(with: messages[0]); state.toggleSelected(messages[1])
        for dark in [false, true] {
            let view = VStack(spacing: 0) {
                ForEach(messages) { message in
                    MessageSelectionRow(state: state, message: message) { MessageBubbleView(ctx: ctx, message: message).padding(.horizontal, 16) }
                        .padding(.vertical, 4)
                }
                Spacer(minLength: 0)
                ChatSelectionBar(model: m, state: state).frame(height: 64)
            }
            .chatServices(ChatServices(chat: Repo()))
            try await render(view, "multi-select\(dark ? "-dark" : "")", width: 720, height: 300, dark: dark)
        }
    }

    func testWallpaperAndStylePickers() async throws {
        var services = ChatServices(chat: Repo()); services.wallpapers = Wallpapers()
        let view = ScrollView { VStack(alignment: .leading, spacing: 16) { ChatStylePicker { _ in }; ChatWallpaperPicker(onSelect: { _ in }, onDim: { _ in }) }.padding(20) }
            .chatServices(services)
        try await render(view, "wallpaper-style-pickers", width: 640, height: 760)
        try await render(view, "wallpaper-style-pickers-dark", width: 640, height: 760, dark: true)
    }

    func testStoragePanel() async throws {
        let view = ScrollView { ChatStoragePanel(limitMb: 2048, onLimitChange: { _ in }).padding(20) }.chatServices(ChatServices(chat: Repo()))
        try await render(view, "storage-panel", width: 560, height: 700, settle: 25)
    }

    func testCropAndGroupAvatarDialogs() async throws {
        let image = NSImage(size: NSSize(width: 800, height: 500), flipped: false) { rect in
            NSGradient(colors: [.systemTeal, .systemIndigo, .systemPink])?.draw(in: rect, angle: 30)
            NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 300, y: 120, width: 200, height: 200)).fill()
            return true
        }
        let png = try XCTUnwrap(NSBitmapImageRep(data: image.tiffRepresentation!)?.representation(using: .png, properties: [:]))
        try await render(ChatAvatarCropDialog(imageData: png, onApply: { _ in }, onCancel: {}), "avatar-crop", width: 680, height: 640)
        let m = model(Repo())
        try await render(ChatGroupAvatarDialog(model: m, chat: RenderData.chats[1], title: "Release Team"), "group-avatar", width: 440, height: 520)
    }

    func testVideoControlsAndTile() async throws {
        let player = ChatVideoPlayer(item: AVPlayerItem(url: URL(fileURLWithPath: "/nonexistent.mov")), loader: nil)
        let view = VStack(spacing: 16) {
            ChatVideoControls(player: player, onToggleFullScreen: {}).frame(width: 640)
            ChatVideoNameBar(name: "Release demo.mp4", size: 48_000_000).frame(width: 320).background(Color.black)
        }
        try await render(view, "video-controls", width: 680, height: 220)
        let state = ChatThreadState(accountId: "a", chat: RenderData.chats[1])
        let file = FileContent(fileId: 9, name: "demo.mp4", size: 48_000_000, time: 1, mimeType: "video/mp4")
        let tile = ChatVideoTile(message: Make.message("v", chat: "g", sender: 2, content: .file(file), mine: false, serverId: 7), file: file, state: state)
            .chatServices(ChatServices(chat: Repo()))
        try await render(tile, "video-tile", width: 360, height: 220)
    }

    func testImageViewerStripAndCard() async throws {
        let images = (1...6).map { ImageContent(fileId: $0, name: "photo\($0).jpg", size: 1000, time: 1) }
        let strip = ChatImageStrip(accountId: "a", images: images, current: images[2]) { _ in }.chatServices(ChatServices(chat: Repo()))
        try await render(strip, "image-strip", width: 520, height: 100)
    }

    /// The viewer over a picture of the app itself, with the chat's other pictures in the strip; sized for a large window.
    func testImageViewerFillsALargeWindow() async throws {
        final class Pictures: StubChatRepository, @unchecked Sendable {
            let images: [ImageContent]
            init(_ images: [ImageContent]) { self.images = images; super.init() }
            override func watchAttachments(accountId: String, chatGid: String) -> AsyncStream<[ChatMessage]> {
                let messages = images.enumerated().map { Make.message("p\($0.offset)", content: .image($0.element), serverId: $0.offset + 1) }
                return AsyncStream { $0.yield(messages); $0.finish() }
            }
            override func loadAttachment(accountId: String, content: MessageContent, thumbnail: Bool) async -> Outcome<Data> {
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1440, pixelsHigh: 900, bitsPerSample: 8, samplesPerPixel: 4,
                                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                NSColor(calibratedRed: 0.62, green: 0.78, blue: 0.55, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 1440, height: 900).fill()
                NSColor.white.setFill(); NSRect(x: 160, y: 120, width: 1120, height: 660).fill()
                NSGraphicsContext.restoreGraphicsState()
                return .success(rep.representation(using: .png, properties: [:])!)
            }
        }
        let images = (1...11).map { ImageContent(fileId: $0, name: "Screenshot 2026-11-17 at 09.19.\($0).png", size: 1_240_000, time: 1) }
        let viewer = ChatImageViewer(accountId: "a", chatGid: "g", image: images[0]).chatServices(ChatServices(chat: Pictures(images)))
        let size = ChatViewerSize.of(window: CGSize(width: 1900, height: 1100))
        XCTAssertEqual(size.width, 1900 * ChatViewerSize.share, accuracy: 0.5)
        XCTAssertEqual(ChatViewerSize.of(window: nil), ChatViewerSize.fallback)
        XCTAssertEqual(ChatViewerSize.of(window: CGSize(width: 600, height: 400)), ChatViewerSize.minimum)
        try await render(viewer, "image-viewer", width: ChatViewerSize.fallback.width, height: ChatViewerSize.fallback.height, settle: 20)
    }
}
