import AppKit
import CoreDomain
import SwiftUI
import XCTest
@testable import CoreUI

/// Ported from: test/core/code_block_test.dart, test/widget/app_toast_test.dart (controller part) and the pure
/// logic of the date field / provider colours / body renderers.
@MainActor
final class WidgetLogicTests: XCTestCase {
    func testCodeBlockShowsFirstLinesUntilExpanded() {
        let code = (1...25).map { "line \($0)" }.joined(separator: "\n")
        XCTAssertEqual(CodeBlock.shownText(code, collapsedLines: 10, expanded: false).components(separatedBy: "\n").count, 10)
        XCTAssertEqual(CodeBlock.shownText(code, collapsedLines: 10, expanded: true), code)
        XCTAssertEqual(CodeBlock.shownText("a\nb", collapsedLines: 10, expanded: false), "a\nb")
        XCTAssertEqual(CodeBlock.shownText(code, collapsedLines: nil, expanded: false), code)
    }

    /// One huge line (a pasted JSON body) takes many rows once wrapped: it collapses like many short lines.
    func testCodeRowsCountWrappedRowsNotLineBreaks() {
        let font = CodeRows.font(size: 12)
        let short = CodeRows.measure("a\nb\nc", font: font, lineSpacing: 2, width: 400)
        XCTAssertEqual(short.count, 3)
        XCTAssertGreaterThan(short.rowHeight, 0)
        let json = "{" + (1...200).map { "\"key\($0)\": \"value \($0)\"" }.joined(separator: ", ") + "}"
        let wrapped = CodeRows.measure(json, font: font, lineSpacing: 2, width: 400)
        XCTAssertGreaterThan(wrapped.count, 10, "one line, many rows")
        let wider = CodeRows.measure(json, font: font, lineSpacing: 2, width: 800)
        XCTAssertLessThan(wider.count, wrapped.count)
        XCTAssertEqual(CodeRows.measure("", font: font, lineSpacing: 2, width: 400).count, 0)
    }

    func testToastsStackNewestFirstCappedAndDeduplicated() {
        let c = AppToastController()
        c.show("a"); c.show("b"); c.show("c"); c.show("d")
        XCTAssertEqual(c.toasts.map(\.message), ["d", "c", "b"])
        c.show("b", kind: .error)
        XCTAssertEqual(c.toasts.map(\.message), ["b", "d", "c"])
        XCTAssertEqual(c.toasts.first?.kind, .error)
        c.dismiss(c.toasts[0].id)
        XCTAssertEqual(c.toasts.map(\.message), ["d", "c"])
        c.dismiss(9999)
        XCTAssertEqual(c.toasts.count, 2)
    }

    func testProviderColorParsing() {
        XCTAssertEqual(ProviderColor.argb(fromHex: "#ff0000"), 0xFFFF0000)
        XCTAssertEqual(ProviderColor.argb(fromHex: "0f0"), 0xFF00FF00)
        XCTAssertNil(ProviderColor.argb(fromHex: "zzz")); XCTAssertNil(ProviderColor.argb(fromHex: nil)); XCTAssertNil(ProviderColor.argb(fromHex: "#12345"))
        XCTAssertGreaterThan(ProviderColor.luminance(0xFFFFFFFF), 0.9)
        XCTAssertLessThan(ProviderColor.luminance(0xFF000000), 0.01)
    }

    func testDateFormatting() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: 2026, month: 5, day: 26, hour: 9, minute: 5))!
        XCTAssertEqual(AppDateFormat.format(d, style: "iso", calendar: cal), "2026-05-26")
        XCTAssertEqual(AppDateFormat.format(d, style: "dmy", withTime: true, calendar: cal), "26/05/2026 09:05")
        XCTAssertEqual(AppDateFormat.parseTime("09:05")?.hour, 9)
        XCTAssertNil(AppDateFormat.parseTime("9:5")); XCTAssertNil(AppDateFormat.parseTime("24:00")); XCTAssertNil(AppDateFormat.parseTime("12:60"))
    }

    func testBrandLogoFallsBackWithoutBundleResources() {
        for t in ProviderType.allCases { _ = BrandLogos.image(for: t, bundle: Bundle(for: Self.self)) }
        let badge = BrandLogoBadge(.zentao, size: 20)
        XCTAssertNotNil(NSHostingView(rootView: badge))
    }

    func testWorkspaceIcons() {
        XCTAssertEqual(WorkspaceIcons.symbol("rocket"), "paperplane")
        XCTAssertNil(WorkspaceIcons.symbol("nope"))
        XCTAssertEqual(WorkspaceIcons.imageData("data:image/png;base64,AQID"), Data([1, 2, 3]))
        XCTAssertNil(WorkspaceIcons.imageData("data:image/png;base64,"))
        XCTAssertNil(WorkspaceIcons.imageData("briefcase"))
    }

    func testIsHtmlBody() {
        XCTAssertTrue(isHtmlBody(.zentao, "<p>hi</p>"))
        XCTAssertFalse(isHtmlBody(.github, "<p>hi</p>"))
        XCTAssertFalse(isHtmlBody(.zentao, "plain text 1 < 2"))
    }

    // MARK: body renderers

    func testMarkdownBlocks() {
        let blocks = MarkdownText.blocks(for: "# Title\n\nHello **world**\n\n- a\n- b\n  - nested\n\n```\ncode\n```\n\n![cat](https://x.dev/c.png)\n\n> quote")
        XCTAssertEqual(blocks.count, 6)
        guard case .text(_, let level) = blocks[0] else { return XCTFail("heading") }
        XCTAssertEqual(level, 1)
        guard case .list(let ordered, _, let items) = blocks[2] else { return XCTFail("list") }
        XCTAssertFalse(ordered); XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[1].count, 2)   // "b" + nested list
        XCTAssertEqual(blocks[3], .code("code"))
        XCTAssertEqual(blocks[4], .image(url: "https://x.dev/c.png", alt: "cat", width: nil))
        guard case .quote = blocks[5] else { return XCTFail("quote") }
        XCTAssertTrue(MarkdownText.blocks(for: "  \n ").isEmpty)
    }

    func testMarkdownTableAndOrderedList() {
        let blocks = MarkdownBlocks.parse("| a | b |\n|---|---|\n| 1 | 2 |\n\n3. x\n4. y")
        guard case .table(let header, let rows) = blocks[0] else { return XCTFail("table") }
        XCTAssertEqual(header.count, 2); XCTAssertEqual(rows.count, 1)
        guard case .list(true, let start, let items) = blocks[1] else { return XCTFail("ol") }
        XCTAssertEqual(start, 3); XCTAssertEqual(items.count, 2)
    }

    func testHtmlBlocks() {
        let blocks = HtmlBlocks.parse("<p>Hello <b>there</b> <a href=\"https://a.dev\">link</a></p><ul><li>one</li><li>two</li></ul>"
            + "<p><img src=\"https://z/file-read-1.png\" width=\"320\"></p><table><tr><th>A</th></tr><tr><td>1</td></tr></table><pre>x\ny</pre>")
        XCTAssertEqual(blocks.count, 5)
        guard case .text(let s, _) = blocks[0] else { return XCTFail("text") }
        XCTAssertEqual(String(s.characters), "Hello there link")
        XCTAssertEqual(s.runs.compactMap(\.link).first?.absoluteString, "https://a.dev")
        guard case .list(false, _, let items) = blocks[1] else { return XCTFail("list") }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(blocks[2], .image(url: "https://z/file-read-1.png", alt: "", width: 320))
        guard case .table(let h, let r) = blocks[3] else { return XCTFail("table") }
        XCTAssertEqual(h.count, 1); XCTAssertEqual(r.count, 1)
        XCTAssertEqual(blocks[4], .code("x\ny"))
    }

    func testViewsInstantiate() {
        let theme = AppTheme()
        let views: [AnyView] = [
            AnyView(MarkdownText("# hi\n- a")), AnyView(HtmlText("<p>hi</p>")), AnyView(CodeBlock("x", fontSize: 12)),
            AnyView(AppSegmentedTabs([AppSegmentedTab(label: "All", active: true, count: 3) {}])),
            AnyView(LabelChips(["a", "b"], colors: ["a": "#ff0000"])),
            AnyView(AppDialogFrame(title: "T", onClose: {}) { Text("body") } actions: { Text("ok") }),
            AnyView(AppMenuPanel(entries: [AppMenuEntry(label: "x")], onSelected: { _ in })),
        ]
        for v in views { XCTAssertNotNil(NSHostingView(rootView: v.environment(\.appTheme, theme))) }
    }
}


// MARK: Link styling (markdown_text.dart `isPlainLink` / `underlineLinksOnHover`), unread badge, copy-link feedback

final class BodyLinkStyleTests: XCTestCase {
    private func linked(_ text: String, _ url: String) -> AttributedString {
        var a = AttributedString(text); a.link = URL(string: url); return a
    }

    func testDefaultStyleChangesNothing() {
        let style = BodyLinkStyle()
        XCTAssertFalse(style.isCustom)
        let text = linked("docs", "https://example.com")
        XCTAssertEqual(style.apply(to: text, hovered: false), text)
    }

    func testUnderlineOnHoverRestsWithoutAndUnderlinesWhenHovered() {
        let style = BodyLinkStyle(underlineOnHover: true)
        let text = linked("docs", "https://example.com")
        XCTAssertNil(style.apply(to: text, hovered: false).runs.first?.underlineStyle)
        XCTAssertEqual(style.apply(to: text, hovered: true).runs.first?.underlineStyle, .single)
    }

    func testPlainLinksOnlyAreExemptFromTheUnderline() {
        let style = BodyLinkStyle(isPlain: { $0.hasPrefix("mention:") })
        var text = linked("@ann", "mention:42")
        text.append(AttributedString(" and "))
        text.append(linked("docs", "https://example.com"))
        let resting = style.apply(to: text, hovered: false)
        let links = resting.runs.filter { $0.link != nil }
        XCTAssertEqual(links.count, 2)
        XCTAssertNil(links[0].underlineStyle, "a mention rests without an underline")
        XCTAssertEqual(links[1].underlineStyle, .single, "an ordinary link keeps its underline")
        XCTAssertEqual(style.apply(to: text, hovered: true).runs.first?.underlineStyle, .single)
    }

    func testTextWithoutLinksIsUntouched() {
        let style = BodyLinkStyle(underlineOnHover: true)
        let text = AttributedString("plain")
        XCTAssertEqual(style.apply(to: text, hovered: false), text)
    }
}

final class UnreadBadgeTests: XCTestCase {
    func testCountIsCappedAt99Plus() {
        XCTAssertEqual(UnreadBadge.label(for: 3), "3")
        XCTAssertEqual(UnreadBadge.label(for: 99), "99")
        XCTAssertEqual(UnreadBadge.label(for: 100), "99+")
    }

    func testCopyLinkFeedbackLastsAboutASecondAndAHalf() { XCTAssertEqual(CopyLinkFeedback.duration, 1.5, accuracy: 0.001) }
}
