/// Ported from: test/features/chat/presentation/chat_text_labels_test.dart
import CoreDomain
import XCTest
@testable import FeatureChat

final class ChatTextLabelsTests: XCTestCase {
    func testTokensSplitMentionsAndAddresses() {
        let t = ChatTextLabels.tokens("hi [@Ann](@#7), see https://x.dev/a?b=1.")
        XCTAssertEqual(t, [.text("hi "), .mention(name: "Ann", userId: 7), .text(", see "), .url("https://x.dev/a?b=1"), .text(".")])
    }

    func testAdjacentTokensGetASpaceBetween() {
        XCTAssertEqual(ChatTextLabels.tokens("[@A](@#1)[@B](@#2)"),
                       [.mention(name: "A", userId: 1), .text(" "), .mention(name: "B", userId: 2)])
    }

    func testAddressWithBracketsKeepsThem() {
        XCTAssertEqual(ChatTextLabels.urls("http://[::1]:8080/x?label[]=bug"), ["http://[::1]:8080/x?label[]=bug"])
        XCTAssertEqual(ChatTextLabels.firstUrl("see (https://a.io/p) now"), "https://a.io/p")
    }

    func testUrlsDeduplicateSameAddress() {
        let text = "https://a.io/p and [https://a.io/p/](https://a.io/p/) and https://A.io/p#frag"
        XCTAssertEqual(ChatTextLabels.urls(text), ["https://a.io/p"], "a trailing slash, the host's case and a #fragment do not make another address")
        XCTAssertEqual(ChatTextLabels.urls("https://b.io/x https://b.io/y"), ["https://b.io/x", "https://b.io/y"])
    }

    func testMentionUserId() {
        XCTAssertEqual(ChatTextLabels.mentionUserId("@#24"), 24)
        XCTAssertEqual(ChatTextLabels.mentionUserId(" @#24 "), 24)
        XCTAssertNil(ChatTextLabels.mentionUserId("https://x.dev"))
    }

    func testMarkdownDetection() {
        XCTAssertTrue(ChatTextLabels.looksLikeMarkdown("# Title"))
        XCTAssertTrue(ChatTextLabels.looksLikeMarkdown("some **bold** text"))
        XCTAssertTrue(ChatTextLabels.looksLikeMarkdown("- item"))
        XCTAssertFalse(ChatTextLabels.looksLikeMarkdown("just words, 5 * 3 = 15"))
        XCTAssertFalse(ChatTextLabels.rendersMarkdown("hello", markdown: true), "no syntax: skips the costlier renderer")
        XCTAssertTrue(ChatTextLabels.rendersMarkdown("**hi**", markdown: true))
    }

    func testShowsWideForCodeAndMarkdownOnly() {
        XCTAssertTrue(ChatTextLabels.showsWide(Make.message(content: .code("x", language: nil, name: nil))))
        XCTAssertTrue(ChatTextLabels.showsWide(Make.message(content: .text("# h\n- a", markdown: true))))
        XCTAssertFalse(ChatTextLabels.showsWide(Make.message(content: .text("hello", markdown: true))))
        XCTAssertFalse(ChatTextLabels.showsWide(Make.message(content: .code("x", language: nil, name: nil), deleted: true)))
    }

    func testPreviewByContentType() {
        XCTAssertEqual(ChatTextLabels.preview(Make.message(content: .text("hi [@Ann](@#7)\n  there", markdown: false))), "hi @Ann there")
        XCTAssertEqual(ChatTextLabels.preview(Make.message(content: .text("# Title\n**bold** and `code`", markdown: true))), "Title bold and code")
        XCTAssertEqual(ChatTextLabels.preview(Make.message(content: .emoji("👍"))), "👍")
        XCTAssertEqual(ChatTextLabels.preview(Make.message(content: .link(url: "https://a.io", title: nil))), "https://a.io")
        XCTAssertEqual(ChatTextLabels.preview(Make.message(content: .code("let a = 1\nlet b", language: nil, name: nil))), "Code: let a = 1")
        XCTAssertEqual(ChatTextLabels.preview(Make.message(content: .code("x", language: nil, name: "snippet.swift"))), "Code: snippet.swift")
        XCTAssertEqual(ChatTextLabels.preview(Make.message(deleted: true)), "Message retracted")
        XCTAssertEqual(ChatTextLabels.preview(Make.message(content: .unsupported("card"))), "Unsupported message (card)")
    }

    func testReactionPreviewOnlyWithReactionsOn() {
        let reaction = Make.message(content: .emoji("👍"), replyTo: 5)
        XCTAssertEqual(ChatTextLabels.preview(reaction, reactions: true), "Reacted 👍")
        XCTAssertEqual(ChatTextLabels.preview(reaction, reactions: false), "👍")
    }

    func testNoticeTextKeepsMentionsAndUnescapes() {
        XCTAssertEqual(ChatTextLabels.noticeText("[@A](@#1) invited [@B](@#2) to [my\\_chat](http://x/y)", markdown: true),
                       "[@A](@#1) invited [@B](@#2) to my_chat")
        XCTAssertEqual(ChatTextLabels.noticeText("**raw**", markdown: false), "**raw**")
    }

    func testUserNameFallbacks() {
        let users = [7: ChatUser(accountId: "a", userId: 7, account: "ann", realname: "Ann Lee"),
                     8: ChatUser(accountId: "a", userId: 8, account: "bob", realname: "")]
        XCTAssertEqual(ChatTextLabels.userName(users, 7), "Ann Lee")
        XCTAssertEqual(ChatTextLabels.userName(users, 8), "bob")
        XCTAssertEqual(ChatTextLabels.userName(users, 0), "Xuanbot")
        XCTAssertEqual(ChatTextLabels.userName(users, 99), "User #99")
    }

    func testDayLabel() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
        XCTAssertEqual(ChatTextLabels.dayLabel(now, now: now, calendar: cal), "Today")
        XCTAssertEqual(ChatTextLabels.dayLabel(now.addingTimeInterval(-86400), now: now, calendar: cal), "Yesterday")
        XCTAssertFalse(ChatTextLabels.dayLabel(now.addingTimeInterval(-5 * 86400), now: now, calendar: cal).isEmpty)
    }

    func testFileHelpers() {
        XCTAssertEqual(ChatTextLabels.fileBadge("report.final.pdf"), "PDF")
        XCTAssertEqual(ChatTextLabels.fileBadge("archive.tar.gzip"), "GZIP")
        XCTAssertEqual(ChatTextLabels.fileBadge("noext"), "FILE")
        XCTAssertEqual(ChatTextLabels.fileBadge("trailing."), "FILE")
        XCTAssertEqual(ChatTextLabels.fileSize(512), "512 B")
        XCTAssertEqual(ChatTextLabels.fileSize(2048), "2 KB")
        XCTAssertEqual(ChatTextLabels.fileSize(3 * 1024 * 1024), "3.0 MB")
        XCTAssertEqual(ChatTextLabels.fileSize(2 << 30), "2 GB")
        XCTAssertEqual(ChatTextLabels.linkHost("https://git.example.com/a/b"), "git.example.com")
    }

    func testAgo() {
        let now = Date()
        XCTAssertEqual(ChatTextLabels.ago(now.addingTimeInterval(-10), now: now), "just now")
        XCTAssertEqual(ChatTextLabels.ago(now.addingTimeInterval(-5 * 60), now: now), "5m ago")
        XCTAssertEqual(ChatTextLabels.ago(now.addingTimeInterval(-2 * 3600), now: now), "2h ago")
        XCTAssertEqual(ChatTextLabels.ago(now.addingTimeInterval(-3 * 86400), now: now), "3d ago")
    }
}
