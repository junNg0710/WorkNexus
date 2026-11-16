/// Ported from: test/features/chat/presentation/message_bubble_test.dart (layout decisions)
import CoreDomain
import CoreUI
import XCTest
@testable import FeatureChat

final class BubbleLayoutTests: XCTestCase {
    private func style(_ a: ChatAppearance) -> ChatStyle { ChatStyle.resolve(a, theme: AppTheme()) }
    private func layout(_ a: ChatAppearance, mine: Bool = false, first: Bool = true, last: Bool = true, group: Bool = true,
                        content: MessageContent = .text("hi"), replyTo: Int? = nil, state: SendState = .sent) -> BubbleLayout {
        BubbleLayout(style: style(a), message: Make.message(content: content, mine: mine, state: state, replyTo: replyTo),
                     firstOfRun: first, lastOfRun: last, showSender: group)
    }

    func testTBChatPointsAtTheAvatarOfTheFirstBubbleOfARun() {
        let first = layout(.tbchat)
        XCTAssertTrue(first.tailed)
        XCTAssertTrue(first.nameOverRow)
        XCTAssertTrue(first.hasAvatarSlot && first.avatarVisible)
        XCTAssertTrue(first.avatarLevel, "the name is over the row, so nothing sits over the bubble")
        XCTAssertEqual(first.tailTip(style: style(.tbchat)), 20, "the avatar's centre: half of 40")
        let next = layout(.tbchat, first: false, last: true)
        XCTAssertFalse(next.tailed)
        XCTAssertFalse(next.avatarVisible)
        XCTAssertNil(next.tailTip(style: style(.tbchat)))
        XCTAssertFalse(next.showName)
    }

    func testTBChatOwnMessagesHaveNoAvatarAndAlignEnd() {
        let own = layout(.tbchat, mine: true)
        XCTAssertFalse(own.hasAvatarSlot)
        XCTAssertTrue(own.alignEnd)
        XCTAssertFalse(own.showName)
        XCTAssertTrue(own.tailed, "own bubbles keep the (mirrored) tail on the run's first message")
    }

    func testTelegramTailOnTheLastOfARunAndAvatarBesideIt() {
        let last = layout(.telegram, first: false, last: true)
        XCTAssertTrue(last.tailed)
        XCTAssertTrue(last.avatarVisible)
        XCTAssertFalse(layout(.telegram, first: true, last: false).tailed)
        XCTAssertFalse(layout(.telegram, group: false).hasAvatarSlot, "Telegram hides avatars in one-to-one chats")
        XCTAssertTrue(layout(.telegram).showName == true)
        XCTAssertFalse(layout(.telegram).nameAbove, "Telegram names sit inside the bubble")
    }

    func testWeChatTailsEveryMessageAndHasAvatarsBothSides() {
        let mid = layout(.wechat, first: false, last: false)
        XCTAssertTrue(mid.tailed)
        XCTAssertTrue(mid.avatarVisible)
        XCTAssertTrue(layout(.wechat, mine: true).hasAvatarSlot)
        XCTAssertFalse(layout(.wechat).showFooter, "WeChat shows times as separators")
    }

    func testZenTaoHeaderNamesEveryRunEvenOwn() {
        let own = layout(.zentao, mine: true)
        XCTAssertTrue(own.headed && own.showName && own.nameAbove)
        XCTAssertFalse(own.alignEnd, "ZenTao keeps own messages on the left")
        XCTAssertFalse(layout(.zentao).showFooter, "the time is in the header")
    }

    func testWorkNexusDefaults() {
        let l = layout(.worknexus)
        XCTAssertFalse(l.tailed)
        XCTAssertTrue(l.nameAbove)
        XCTAssertTrue(l.showFooter == true)
        XCTAssertFalse(layout(.worknexus, first: true, last: false).showFooter, "time under the last message of a run")
        XCTAssertEqual(l.gutter(style: style(.worknexus)).leading, 0)
    }

    func testFooterAlwaysShowsWhileNotSent() {
        XCTAssertTrue(layout(.wechat, state: .failed).showFooter)
        XCTAssertTrue(layout(.zentao, state: .pending).showFooter)
    }

    func testGutterKeepsTheTailRoomOnTheAvatarSide() {
        let g = layout(.tbchat).gutter(style: style(.tbchat))
        XCTAssertEqual(g.leading, BubbleTail.width)
        XCTAssertEqual(g.trailing, 0)
        let own = layout(.tbchat, mine: true).gutter(style: style(.tbchat))
        XCTAssertEqual(own.leading, 0)
        XCTAssertEqual(own.trailing, BubbleTail.width)
    }

    func testMediaIsBareUnlessItQuotes() {
        let image = MessageContent.image(ImageContent(fileId: 1, name: "a.png", size: 1, time: 1))
        XCTAssertTrue(layout(.tbchat, content: image).media)
        XCTAssertTrue(layout(.tbchat, content: .emoji("👍")).media)
        let quoting = layout(.tbchat, content: image, replyTo: 3)
        XCTAssertFalse(quoting.media, "a reply with an image sits in a bubble with its quote")
        XCTAssertTrue(quoting.hasQuote)
        XCTAssertFalse(layout(.tbchat, content: image).tailed, "media has no bubble to carry a tail")
    }

    func testQuoteAboveStyleLowersTheAvatarLevel() {
        // A style with its quote above the bubble: the avatar no longer lines up with the bubble's top.
        var s = style(.tbchat)
        s.quote = .above
        let l = BubbleLayout(style: s, message: Make.message(replyTo: 3), firstOfRun: true, lastOfRun: true, showSender: true)
        XCTAssertFalse(l.avatarLevel)
    }

    func testDeletedMessageHasNoQuote() {
        let l = BubbleLayout(style: style(.tbchat), message: Make.message(replyTo: 3, deleted: true), firstOfRun: true, lastOfRun: true, showSender: true)
        XCTAssertFalse(l.hasQuote)
    }
}
