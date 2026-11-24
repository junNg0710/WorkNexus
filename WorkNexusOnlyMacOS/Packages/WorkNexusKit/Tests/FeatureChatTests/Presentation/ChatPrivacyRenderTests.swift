/// Ported from: test/widget/chat_privacy_settings_test.dart + privacy_mask_test.dart (what each part looks like hidden)
import AppKit
import CoreDomain
import CoreUI
import SwiftUI
import XCTest
@testable import FeatureChat

/// Renders chat-list rows and message bubbles with the privacy mode off and on (catches layout crashes) and writes PNGs to
/// `/tmp/wn-chat-render` (or the folder `WN_CHAT_RENDER` names) so they can be looked at.
@MainActor
final class ChatPrivacyRenderTests: XCTestCase {
    private let all = ShouldHideChatPart().hiddenParts(ChatPrivacy(enabled: true))

    private func render<V: View>(_ view: V, _ name: String, width: CGFloat, height: CGFloat, dark: Bool = false) async throws {
        var settings = AppSettings(); if dark { settings.variant = .dark; settings.themeFollowsSystem = false }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.environment(\.appTheme, theme).frame(width: width, height: height).background(theme.colors.bg))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        // Long enough for the masks' ease (0.18 s) to settle.
        for _ in 0..<12 { try await Task.sleep(for: .milliseconds(40)); host.layoutSubtreeIfNeeded() }
        let folder = ProcessInfo.processInfo.environment["WN_CHAT_RENDER"] ?? "/tmp/wn-chat-render"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
    }

    private var rows: [ConversationRowData] {
        let users = [2: ShellMake.user(2, "Bình Nguyen", role: "pm", status: "online")]
        var direct = ShellMake.chat("d", type: .one2one, peer: 2, at: Make.t0.timeIntervalSince1970, unread: 2)
        direct.lastMessage = Make.message("m1", chat: "d", sender: 2, content: .text("The build is green, shipping at 5"))
        var group = ShellMake.chat("g", name: "Release Team", at: Make.t0.timeIntervalSince1970 - 600, starred: true)
        group.lastMessage = Make.message("m2", sender: 3, content: .text("Please review the notes"))
        return [ConversationRowData(chat: direct, title: "Bình Nguyen", users: users, lastSender: nil, typing: nil),
                ConversationRowData(chat: group, title: "Release Team", users: [:], lastSender: "An", typing: nil)]
    }

    func testChatListRowsHideNamesAvatarsAndPreviews() async throws {
        for hidden in [false, true] {
            let view = VStack(spacing: 0) {
                ForEach(rows, id: \.chat.gid) { ConversationTile(chat: $0, selected: false, highlighted: false, compact: false) }
                Spacer(minLength: 0)
            }
            .chatPrivacy(hiding: hidden ? all : [])
            try await render(view, "privacy-list\(hidden ? "-hidden" : "")", width: 340, height: 160)
        }
    }

    func testBubblesFadeWordsAndCoverPictures() async throws {
        let state = ChatThreadState(accountId: "a", chat: Make.chat("g"))
        state.users = [2: ShellMake.user(2, "Bình Nguyen"), 3: ShellMake.user(3, "An")]; state.selfUserId = 1
        let services = ChatServices(chat: StubChatRepository())
        let ctx = ThreadContext(model: MessageTimelineModel(state: state, services: services), actions: ChatThreadActions())
        let messages = [
            Make.message("m1", sender: 2, content: .text("Login fails on Safari after the last deploy"), serverId: 5),
            Make.message("m2", sender: 3, at: Make.t0.addingTimeInterval(60),
                         content: .image(ImageContent(fileId: 9, name: "screen.png", size: 1000, time: 0, width: 320, height: 180)), serverId: 6),
            Make.message("m3", sender: 3, at: Make.t0.addingTimeInterval(90), content: .emoji("😀"), serverId: 7),
            Make.message("m4", sender: 1, at: Make.t0.addingTimeInterval(120), content: .text("I'll file a bug"), mine: true, serverId: 8),
        ]
        for (hidden, dark) in [(false, false), (true, false), (true, true)] {
            let view = VStack(spacing: 8) {
                ForEach(messages) { MessageBubbleView(ctx: ctx, message: $0).padding(.horizontal, 16) }
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .background { ChatWallpaperView() }
            .chatStyleScope()
            .chatServices(services)
            .chatPrivacy(hiding: hidden ? all : [])
            try await render(view, "privacy-bubbles\(hidden ? "-hidden" : "")\(dark ? "-dark" : "")", width: 560, height: 520, dark: dark)
        }
    }

    func testHiddenInfoPlaceholdersLayOut() async throws {
        let view = VStack(alignment: .leading, spacing: 12) {
            ChatHiddenMediaGrid(count: 6)
            ChatHiddenFileRow()
            HStack { ChatPrivacyAvatarFace(group: false, side: 40).frame(width: 40, height: 40).clipShape(Circle())
                     ChatPrivacyAvatarFace(group: true, side: 40).frame(width: 40, height: 40).clipShape(Circle()) }
            Spacer(minLength: 0)
        }
        .padding(16)
        try await render(view, "privacy-info-placeholders", width: 320, height: 300)
    }
}
