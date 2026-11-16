/// Ported from: test/core/theme/chat_style_palette_test.dart, chat_style_specs
import CoreDomain
import CoreUI
import SwiftUI
import XCTest
@testable import FeatureChat

final class ChatStyleTests: XCTestCase {
    func testLuminanceAndContrast() {
        XCTAssertEqual(ChatColor(0xFF00_0000).luminance, 0, accuracy: 1e-9)
        XCTAssertEqual(ChatColor(0xFFFF_FFFF).luminance, 1, accuracy: 1e-9)
        XCTAssertEqual(ChatColor.contrast(ChatColor(0xFF00_0000), ChatColor(0xFFFF_FFFF)), 21, accuracy: 1e-6)
    }

    func testAlphaBlend() {
        let blended = ChatColor(0x8000_0000).over(ChatColor(0xFFFF_FFFF))
        XCTAssertEqual(blended.a, 1, accuracy: 1e-9)
        XCTAssertEqual(blended.r, 1 - 128.0 / 255, accuracy: 1e-6)
        XCTAssertEqual(ChatColor.clear.over(ChatColor(0xFF12_3456)), ChatColor(0xFF12_3456))
    }

    func testReadableOnKeepsHueAndReachesTheRatio() {
        let green = ChatColor(0xFF0D_CC61)
        let white = ChatColor(0xFFFF_FFFF)
        let fixed = ChatColor.readable(green, on: white, towards: ChatColor(0xFF00_0000))
        XCTAssertGreaterThanOrEqual(ChatColor.contrast(fixed, white), 4.5)
        XCTAssertGreaterThan(fixed.g, fixed.r)
        // Already readable: unchanged.
        XCTAssertEqual(ChatColor.readable(ChatColor(0xFF00_0000), on: white, towards: green), ChatColor(0xFF00_0000))
    }

    func testEveryPaletteTextReadsOnItsBubble() {
        let palettes: [(String, ChatStylePalette)] = [
            ("tgDay", .telegramDay), ("tgNight", .telegramNight), ("zaloL", .zaloLight), ("zaloD", .zaloDark),
            ("ztL", .zentaoLight), ("ztD", .zentaoDark), ("wcL", .wechatLight), ("wcD", .wechatDark),
            ("tbL", .tbchatLight), ("tbD", .tbchatDark),
        ]
        for (name, p) in palettes {
            XCTAssertGreaterThanOrEqual(ChatColor.contrast(p.incomingText, p.incomingBubble), 7, "\(name) incoming text")
            // WeChat's own night green is the one bubble the real client leaves just under 7:1.
            XCTAssertGreaterThanOrEqual(ChatColor.contrast(p.outgoingText, p.outgoingBubble), name == "wcD" ? 6.4 : 7, "\(name) outgoing text")
            XCTAssertGreaterThanOrEqual(ChatColor.contrast(p.incomingMeta, p.incomingBubble), 4.5, "\(name) incoming meta")
            XCTAssertGreaterThanOrEqual(ChatColor.contrast(p.outgoingMeta, p.outgoingBubble), 4.5, "\(name) outgoing meta")
            XCTAssertGreaterThanOrEqual(ChatColor.contrast(p.incomingLink, p.incomingBubble), 4.5, "\(name) incoming link")
            XCTAssertGreaterThanOrEqual(ChatColor.contrast(p.outgoingLink, p.outgoingBubble), 4.5, "\(name) outgoing link")
        }
    }

    func testPrimaryBubblesTintOwnBubbleWithTheAccent() {
        let accent = ChatColor(0xFF5A_57D6)
        let p = ChatStylePalette.tbchatLight.withPrimaryBubbles(accent: accent, dark: false)
        XCTAssertEqual(p.outgoingBubble, accent.opacity(0.16).over(ChatStylePalette.tbchatLight.incomingBubble))
        XCTAssertEqual(p.outgoingText, ChatStylePalette.tbchatLight.incomingText)
        XCTAssertEqual(p.outgoingLink, accent)
        XCTAssertNotNil(p.outgoingBorder)
        XCTAssertNil(p.outgoingQuoteFill)
        // Telegram's ticks follow the accent; a style without ticks stays without.
        XCTAssertEqual(ChatStylePalette.telegramDay.withPrimaryBubbles(accent: accent, dark: false).outgoingTicks, accent)
        XCTAssertNil(ChatStylePalette.zaloLight.withPrimaryBubbles(accent: accent, dark: false).outgoingTicks)
    }

    func testResolveUsesTheThemeBackgroundForEveryStyle() {
        let theme = AppTheme()
        for a in ChatAppearance.allCases {
            let s = ChatStyle.resolve(a, theme: theme)
            XCTAssertEqual(s.palette.background, ChatColor(theme.colors.bg), "\(a)")
        }
    }

    func testTBChatSpec() {
        let s = ChatStyle.resolve(.tbchat, theme: AppTheme())
        XCTAssertEqual(s.avatarSize, 40)
        XCTAssertEqual(s.avatarShape, .circle)
        XCTAssertEqual(s.tail, .triangleTop)
        XCTAssertEqual(s.name, .aboveRow)
        XCTAssertEqual(s.time, .insideAligned)
        XCTAssertEqual(s.avatar, .firstOfRun)
        XCTAssertEqual(s.radius, 12)
        XCTAssertEqual(s.joinRadius, 12)
        XCTAssertFalse(s.ownAvatar)
        XCTAssertTrue(s.timeAtEnd(alignEnd: true))
        XCTAssertFalse(s.alignEnd(mine: false))
    }

    func testPrimaryBubblesSettingLeavesTheDefaultStyleAlone() {
        let theme = AppTheme()
        let plain = ChatStyle.resolve(.worknexus, theme: theme)
        let primary = ChatStyle.resolve(.worknexus, theme: theme, primaryBubbles: true)
        XCTAssertEqual(plain.palette, primary.palette)
        let tg = ChatStyle.resolve(.telegram, theme: theme)
        XCTAssertNotEqual(tg.palette.outgoingBubble, ChatStyle.resolve(.telegram, theme: theme, primaryBubbles: true).palette.outgoingBubble)
    }

    func testTelegramTailCornerIsSquareOnTheSenderSide() {
        let s = ChatStyle.resolve(.telegram, theme: AppTheme())
        let incoming = s.corners(mine: false, firstOfRun: true, lastOfRun: true, withTail: true)
        XCTAssertEqual(incoming.bottomLeft, 0)
        XCTAssertEqual(incoming.topLeft, 16)
        XCTAssertEqual(incoming.bottomRight, 16)
        let own = s.corners(mine: true, firstOfRun: true, lastOfRun: true, withTail: true)
        XCTAssertEqual(own.bottomRight, 0)
        XCTAssertEqual(own.bottomLeft, 16)
    }

    func testJoinRadiusWithinARun() {
        let s = ChatStyle.resolve(.telegram, theme: AppTheme())
        let middle = s.corners(mine: false, firstOfRun: false, lastOfRun: false, withTail: false)
        XCTAssertEqual(middle.topLeft, 6)
        XCTAssertEqual(middle.bottomLeft, 6)
        XCTAssertEqual(middle.topRight, 16)
        let first = s.corners(mine: false, firstOfRun: true, lastOfRun: false, withTail: false)
        XCTAssertEqual(first.topLeft, 16)
        XCTAssertEqual(first.bottomLeft, 6)
        let last = s.corners(mine: true, firstOfRun: false, lastOfRun: true, withTail: false)
        XCTAssertEqual(last.topRight, 6)
        XCTAssertEqual(last.bottomRight, 16)
    }

    func testWeChatTriangleKeepsSquareishCorners() {
        let s = ChatStyle.resolve(.wechat, theme: AppTheme())
        XCTAssertEqual(s.corners(mine: false, firstOfRun: true, lastOfRun: true, withTail: true), BubbleCorners(all: 4))
        XCTAssertEqual(s.separatorGap, 300)
    }

    func testNameColorWrapsAndFallsBack() {
        let s = ChatStyle.resolve(.telegram, theme: AppTheme())
        XCTAssertEqual(s.nameColor(0), s.nameColor(8))
        XCTAssertNotEqual(s.nameColor(0), s.nameColor(1))
        let plain = ChatStyle.resolve(.zalo, theme: AppTheme())
        XCTAssertEqual(plain.nameColor(3), plain.palette.incomingMeta)
    }

    func testOwnInkUsesOutgoingColours() {
        let s = ChatStyle.resolve(.zentao, theme: AppTheme())
        XCTAssertEqual(s.ink(mine: true).text, s.palette.outgoingText)
        XCTAssertEqual(s.ink(mine: false).link, s.palette.incomingLink)
        XCTAssertEqual(s.ink(mine: false).fontSize, 14)
        XCTAssertTrue(s.alignEnd(mine: true) == false, "ZenTao keeps own messages on the left")
    }
}
