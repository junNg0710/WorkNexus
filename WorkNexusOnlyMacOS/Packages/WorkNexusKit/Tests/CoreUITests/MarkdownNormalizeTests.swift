import XCTest
@testable import CoreUI

/// Ported from: test/core/markdown_normalize_test.dart, test/core/link_url_test.dart
final class MarkdownNormalizeTests: XCTestCase {
    func testBackslashEscapes() {
        XCTAssertEqual(normalizeMarkdown("1\\. Open a market\n\\- Missing \\[card\\]"), "1. Open a market\n- Missing [card]")
    }
    func testEscapedAsteriskStaysAMark() { XCTAssertEqual(normalizeMarkdown("a \\*b\\* c"), "a ∗b∗ c") }
    func testUnderscoreBold() {
        XCTAssertEqual(normalizeMarkdown("__Ad :)__ and some_var__x `__code__`"), "**Ad :)** and some_var__x `__code__`")
    }
    func testReferenceLinksInlined() {
        let text = "![Alt text][id] and [docs][]\n\n[id]: https://x.dev/cat.jpg  \"The Dojocat\"\n[docs]: <https://x.dev/docs>"
        XCTAssertEqual(normalizeMarkdown(text), "![Alt text](https://x.dev/cat.jpg) and [docs](https://x.dev/docs)\n")
    }
    func testTitlesDropped() {
        XCTAssertEqual(normalizeMarkdown("![Cat](https://x.dev/c.jpg \"The Cat\") [a](b 't')"), "![Cat](https://x.dev/c.jpg) [a](b)")
    }
    func testItalicAndPlusBullets() {
        XCTAssertEqual(normalizeMarkdown("+ _It_ is some_snake_case\n  + nested"), "- *It* is some_snake_case\n  - nested")
    }
    func testEmptyQuoteLineKeepsQuote() { XCTAssertEqual(normalizeMarkdown("> one\n>\n> two"), "> one\n>\u{00A0}\n> two") }
    func testFootnotes() {
        let text = "One[^first]. Two^[Inline note]. Again[^first].\n\n[^first]: Footnote **markup**\n\n    and more.\n\nAfter."
        XCTAssertEqual(normalizeMarkdown(text),
                       "One¹. Two². Again¹.\n\nAfter.\n\n---\n1. Footnote **markup** and more.\n2. Inline note")
    }
    func testDefinitionListsContainersAbbreviations() {
        let text = "Term 1\n\n:   Definition 1\n  ~ Definition 2\n*[HTML]: Hyper Text\n::: warning\n*here*\n:::"
        XCTAssertEqual(normalizeMarkdown(text), "Term 1\n\n- Definition 1\n- Definition 2\n> **warning**\n> *here*")
    }
    func testFencedAndIndentedCodeLeftAlone() {
        let text = "```\n__x__\n[id]: https://a\n```\n    __y__"
        XCTAssertEqual(normalizeMarkdown(text), text)
    }
    func testSplitsJammedMentions() {
        XCTAssertEqual(normalizeMarkdown("hi @User1@User2@Ba"), "hi @User1 @User2 @Ba")
        XCTAssertEqual(normalizeMarkdown("@An@Bình."), "@An @Bình.")
    }
    func testLeavesPackagesAndHandlesWhole() {
        for t in ["npm i @angular/core@17.0.0", "add @types/node@20", "follow @user@mastodon.social", "mail me@example.com"] {
            XCTAssertEqual(normalizeMarkdown(t), t, t)
        }
    }

    func testPlainChatTextHasNoMarkdown() {
        for t in ["cái này trả chung kết quả API hay riêng vậy anh", "ok 2*3 = 6, see https://example.com/a_b_c",
                  "[@Thanh](@#40) check this", "snake_case_name and 5 - 3"] {
            XCTAssertFalse(hasMarkdownSyntax(t), t)
        }
    }
    func testMarkdownIsRecognised() {
        for t in ["# Title", "- item", "1. first", "> quoted", "```\ncode\n```", "run `make codegen`", "**bold** text",
                  "__bold__ text", "an *italic* word", "~~gone~~", "[docs](https://x.dev)", "| a | b |", "---"] {
            XCTAssertTrue(hasMarkdownSyntax(t), t)
        }
    }

    func testLinkifyBareAddress() {
        XCTAssertEqual(
            linkifyBareUrls("http://mac-mini-2.local:8080/#/builds/actions/ci.reposts\n- Login discord -> New build"),
            "[http://mac-mini-2.local:8080/#/builds/actions/ci.reposts](http://mac-mini-2.local:8080/#/builds/actions/ci.reposts)\n- Login discord -> New build")
    }
    func testLinkifyKeepsSentencePunctuationOutside() {
        XCTAssertEqual(linkifyBareUrls("see https://a.dev/x."), "see [https://a.dev/x](https://a.dev/x).")
    }
    func testLinkifyAutolink() { XCTAssertEqual(linkifyBareUrls("<https://a.dev>"), "[https://a.dev](https://a.dev)") }
    func testLinkifyLeavesExistingAlone() {
        let text = "[docs](https://a.dev) [@Thanh](@#24) ![i](https://a.dev/i.png) `https://a.dev`\n```\nhttps://a.dev\n```"
        XCTAssertEqual(linkifyBareUrls(text), text)
    }

    // link_url_test
    func testNormalizeLinkUrl() {
        XCTAssertEqual(normalizeLinkUrl(" https://a.com/x?y=1 "), "https://a.com/x?y=1")
        XCTAssertEqual(normalizeLinkUrl("http://localhost:8080"), "http://localhost:8080")
        XCTAssertEqual(normalizeLinkUrl("example.com/page"), "https://example.com/page")
        XCTAssertEqual(normalizeLinkUrl("mailto:a@b.co"), "mailto:a@b.co")
        for bad in ["", "hello", "a b.com", "ftp://a.com", "mailto:"] { XCTAssertNil(normalizeLinkUrl(bad), bad) }
    }
}
