import XCTest
@testable import FeatureChat

/// Ports of test/domain/chat/{parse_message_content,emoji,fold_search_text,repair_mentions,is_single_emoji,tidy_markdown_emphasis}_test.dart.
final class ParseAndTextTests: XCTestCase {
    let parse = ParseMessageContent()

    func testPlainAndTextAreBothText() {
        XCTAssertEqual(parse("plain", "hi [@Dyno](@#31)"), .text("hi [@Dyno](@#31)", markdown: false))
        XCTAssertEqual(parse("text", "1"), .text("1", markdown: true))
    }

    func testJammedMentionsAreSplitHandlesAreNot() {
        XCTAssertEqual(parse("plain", "@An@Binh hi"), .text("@An @Binh hi", markdown: false))
        for t in ["ping @alice@mastodon.social", "see https://mastodon.social/@alice@other.instance", "mail me@example.com"] {
            XCTAssertEqual(parse("plain", t), .text(t, markdown: false), t)
        }
    }

    func testImageContentAsSentByServer() {
        XCTAssertEqual(
            parse("image", #"{"name":"image.png","size":52247,"send":true,"type":"image/png","id":27338,"time":1790842835000,"width":712,"height":579}"#),
            .image(ImageContent(fileId: 27338, name: "image.png", size: 52247, time: 1_790_842_835_000, mimeType: "image/png", width: 712, height: 579)))
    }

    func testFileContentToleratesNumericStrings() {
        XCTAssertEqual(parse("file", #"{"name":"spec.pdf","size":"1024","id":"9","time":5}"#),
                       .file(FileContent(fileId: 9, name: "spec.pdf", size: 1024, time: 5)))
    }

    func testUrlObjectsBecomeLinkCards() {
        XCTAssertEqual(parse("object", #"{"type":"url","url":"https://zt/task-view-12406.html","title":"Task 12406"}"#),
                       .link(url: "https://zt/task-view-12406.html", title: "Task 12406"))
    }

    func testMalformedDegradesToUnsupported() {
        XCTAssertEqual(parse("image", "not json"), .unsupported("image"))
        XCTAssertEqual(parse("image", #"{"name":"x.png"}"#), .unsupported("image"))
        XCTAssertEqual(parse("object", #"{"type":"card"}"#), .unsupported("object"))
        XCTAssertEqual(parse("emoticon", ":)"), .unsupported("emoticon"))
    }

    func testImageStillUploadingKeepsSize() {
        XCTAssertEqual(parse("image", #"{"name":"shot.png","size":68,"width":320,"height":200}"#),
                       .image(ImageContent(fileId: 0, name: "shot.png", size: 68, time: 0, width: 320, height: 200)))
    }

    func testDropsLostObjectPlaceholders() {
        XCTAssertEqual(parse("plain", "see \u{FFFC} this"), .text("see  this", markdown: false))
        XCTAssertEqual(parse("plain", "\u{FFFC}"), .unsupported("object"))
        XCTAssertEqual(parse("text", " \u{FFFC}\u{FFFC} "), .unsupported("object"))
    }

    func testCodeSnippets() {
        XCTAssertEqual(parse("code", #"{"lang":"go","code":"x := `raw`\n","name":"main.go"}"#), .code("x := `raw`\n", language: "go", name: "main.go"))
        XCTAssertEqual(parse("code", #"{"lang":"text","code":"abc","name":""}"#), .code("abc", language: "text", name: nil))
        XCTAssertEqual(parse("code", #"{"lang":"text"}"#), .unsupported("code"))
    }

    func testNotificationCard() {
        let c = parse("notification", #"{"title":"T","content":"{\"objectName\":\"Fix it\",\"id\":5,\"count\":3,\"cardURL\":\"https://z/bug-view-5.html\",\"headTitle\":\"Proj\"}","url":"xxc:openInApp/zentao/https%3A%2F%2Fz%2Fx"}"#)
        guard case .notification(let n) = c else { return XCTFail() }
        XCTAssertEqual(n.title, "T"); XCTAssertEqual(n.text, "#5 Fix it (+2)"); XCTAssertEqual(n.url, "https://z/bug-view-5.html")
        XCTAssertEqual(n.subtitle, "Proj"); XCTAssertFalse(n.markdown)
    }

    // MARK: emoji

    func testEncodeKnownEmojiAndEntities() {
        let encode = EncodeEmoji()
        XCTAssertEqual(encode("👍"), ":thumbsup:")
        XCTAssertEqual(encode("ok 😂!"), "ok :joy:!")
        XCTAssertEqual(encode("🦀"), ":crab:")
        XCTAssertEqual(encode("𝔸"), "&#x1D538;")
        XCTAssertEqual(encode("Tiếng Việt ❤"), "Tiếng Việt ❤")
    }

    func testDecodeShortnamesAliasesEntities() {
        let decode = DecodeEmoji()
        XCTAssertEqual(decode(":thumbsup: :+1:"), "👍 👍")
        XCTAssertEqual(decode("&#x1F980; &#128077;"), "🦀 👍")
        XCTAssertEqual(decode("at 10:30: done :unknown:"), "at 10:30: done :unknown:")
    }

    func testFlagsAndSkinTonesGoWhole() {
        XCTAssertEqual(DecodeEmoji()(":flag_vn: :metal_tone5:"), "🇻🇳 🤘🏿")
        XCTAssertEqual(EncodeEmoji()("🇻🇳 🤘🏿"), ":flag_vn: :metal_tone5:")
        XCTAssertEqual(EncodeEmoji()("☺️ 👍️"), "☺️ :thumbsup:")
    }

    func testRoundTrip() {
        let text = "Xong rồi 👍🎉 🦀 🇻🇳 🤘🏿"
        XCTAssertEqual(DecodeEmoji()(EncodeEmoji()(text)), text)
    }

    func testLargeEmojiContent() {
        XCTAssertEqual(parse("image", #"{"type":"emoji","content":":smile:"}"#), .emoji("😄"))
        XCTAssertEqual(parse("emotion", #"{"type":"emoji","content":":thumbsup:"}"#), .emoji("👍"))
        XCTAssertEqual(parse("emotion", ":smile:"), .emoji("😄"))
        XCTAssertEqual(parse("emotion", ":no_such_emoji:"), .text(":no_such_emoji:", markdown: false))
    }

    func testIsSingleEmoji() {
        let single = IsSingleEmoji()
        XCTAssertTrue(single("👍")); XCTAssertTrue(single(" 👍\u{FE0F} ")); XCTAssertFalse(single("👍👍")); XCTAssertFalse(single("hi"))
    }

    // MARK: search folding

    func testFoldDropsCaseAndDiacritics() {
        let fold = FoldSearchText()
        XCTAssertEqual(fold("Đường Phố HỒ CHÍ MINH"), "duong pho ho chi minh")
        XCTAssertEqual(fold("Việt Nam ưu tiên"), "viet nam uu tien")
        XCTAssertEqual(fold("Vie\u{0323}\u{0302}t"), "viet")
        XCTAssertEqual(fold("  xin \n  chào  "), "xin chao")
    }

    func testFoldOfMessage() {
        let fold = FoldSearchText()
        // A file and a picture by their name, a shared link by its address and title, code by its name and what it says.
        XCTAssertEqual(fold.ofMessage(contentType: "image", content: #"{"name":"Ảnh A.png"}"#), "anh a.png")
        XCTAssertEqual(fold.ofMessage(contentType: "file", content: #"{"name":"Báo cáo.zip","size":3}"#), "bao cao.zip")
        XCTAssertEqual(fold.ofMessage(contentType: "object", content: #"{"type":"url","url":"https://zt.test/bug-view-4158.html"}"#), "https://zt.test/bug-view-4158.html")
        XCTAssertEqual(fold.ofMessage(contentType: "code", content: #"{"lang":"swift","code":"print(1)","name":"Demo"}"#), "demo print(1)")
        XCTAssertNil(fold.ofMessage(contentType: "emotion", content: "smile"), "nothing to search in an emoji")
        XCTAssertEqual(fold.ofMessage(contentType: "plain", content: "hỏi [@Thành](@#40) nhé"), "hoi @thanh nhe")
        XCTAssertEqual(fold.ofMessage(contentType: "plain", content: "ok :thumbsup:"), "ok 👍")
        XCTAssertEqual(fold.ofMessage(contentType: "text", content: "**Gấp**: sửa `snake_case` ~~cũ~~"), "gap: sua snake_case cu")
        XCTAssertEqual(fold.ofMessage(contentType: "text", content: "xem [docs](https://x.io)"), "xem docs https://x.io")
        XCTAssertEqual(fold.ofMessage(contentType: "plain", content: "2*3"), "2*3")
    }

    // MARK: mention repair

    func testRepairDropsNameTailAfterMention() {
        XCTAssertEqual(Mentions.repair("hi [@Ian-Lee-Dev](@#12)-Lee-Dev, ok [@Quinn_Dev_501](@#77) done"),
                       "hi [@Ian-Lee-Dev](@#12), ok [@Quinn_Dev_501](@#77) done")
    }

    func testRepairUnwrapsNestedMention() {
        XCTAssertEqual(Mentions.repair("[[@Fiona_Hall](@#21)-Tail7](@#21) task complete"), "[@Fiona_Hall](@#21) task complete")
    }

    func testRepairDropsTailStartingWithSpace() {
        XCTAssertEqual(Mentions.repair("hello [@Ian Lee-Dev](@#9) Lee-Dev resolved"), "hello [@Ian Lee-Dev](@#9) resolved")
    }

    func testRepairKeepsNonTails() {
        let t = "[@Rachel_Lee](@#11) info [@Module-Core](@#12)-Detail"
        XCTAssertEqual(Mentions.repair(t), t)
    }

    func testRepairSeparatesAdjacentMentions() {
        XCTAssertEqual(Mentions.repair("cc: [@A_B](@#1)[@C-D-Dev](@#2)[@E](@#3)"), "cc: [@A_B](@#1) [@C-D-Dev](@#2) [@E](@#3)")
        XCTAssertEqual(Mentions.repair("fyi: @Ann_Lee@Bob-Ops-Dev@Cy"), "fyi: @Ann_Lee @Bob-Ops-Dev @Cy")
    }

    func testTidyMarkdownEmphasis() {
        let tidy = TidyMarkdownEmphasis()
        XCTAssertEqual(tidy("**word **x"), "**word** x")
        XCTAssertEqual(tidy("~~a b ~~"), "~~a b~~ ")
        XCTAssertEqual(tidy("*it *"), "*it* ")
        XCTAssertEqual(tidy("2 * 3 * 4"), "2 * 3 * 4")
    }
}
