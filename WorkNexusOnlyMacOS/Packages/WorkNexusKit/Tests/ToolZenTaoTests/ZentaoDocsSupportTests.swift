import CoreDomain
import CoreUI
import SwiftUI
import XCTest
@testable import ToolZenTao

/// Ported from: test/unit/zentao_doc_prepare_test.dart, test/widget/zentao_doc_body_test.dart (the HTML walk),
/// zentao_doc_find_outline_test.dart (the reader's find / outline state) and the file-preview kinds.
@MainActor
final class ZentaoDocsSupportTests: XCTestCase {
    // MARK: prepareZentaoDocHtml

    func testHeadingsH1ToH4AreAnchoredAndListedInOrder() {
        let p = prepareZentaoDocHtml("<h1>API</h1><p>x</p><h3><strong>Auth</strong></h3><h5>skip</h5><h2> </h2>")
        XCTAssertEqual(p.headings, [ZentaoDocHeading(level: 1, text: "API", index: 0), ZentaoDocHeading(level: 3, text: "Auth", index: 1)])
        XCTAssertTrue(p.html.contains("<h1><zt-anchor data-heading=\"0\"></zt-anchor>API"), p.html)
    }

    func testMatchesAreMarkedCaseInsensitivelyInReadingOrder() {
        let p = prepareZentaoDocHtml("<p>Token <b>token</b></p><pre><code>TOKEN=1</code></pre>", query: "token")
        XCTAssertEqual(p.matchCount, 3)
        let marks = p.root.elements(named: ["mark"])
        XCTAssertEqual(marks.map(\.textContent), ["Token", "token", "TOKEN"])
        XCTAssertEqual(marks.map { $0.attr("data-find") }, ["0", "1", "2"])
    }

    func testTheQueryIsLiteralTextNotAPattern() {
        XCTAssertEqual(prepareZentaoDocHtml("<p>a.b axb</p>", query: "a.b").matchCount, 1)
    }

    func testNoQueryLeavesTheTextAlone() {
        let p = prepareZentaoDocHtml("<p>Token</p>", query: "  ")
        XCTAssertEqual(p.matchCount, 0)
        XCTAssertFalse(p.html.contains("<mark"))
    }

    func testMarksAreFoundBackWithTheirRangesInACodeBlock() throws {
        let p = prepareZentaoDocHtml("<pre><code>GET /a\nGET /b</code></pre>", query: "get")
        let pre = try XCTUnwrap(p.root.elements(named: ["pre"]).first)
        XCTAssertEqual(zentaoFindRanges(pre), [ZentaoFindRange(index: 0, start: 0, end: 3), ZentaoFindRange(index: 1, start: 7, end: 10)])
        XCTAssertEqual(pre.textContent, "GET /a\nGET /b")
    }

    func testAMatchOfTheSameTextTwiceInOneNodeKeepsTheTextBetween() {
        let p = prepareZentaoDocHtml("<p>ab-AB-ab</p>", query: "ab")
        XCTAssertEqual(p.matchCount, 3)
        XCTAssertEqual(p.root.textContent, "ab-AB-ab")
    }

    func testMoreMatchesThanTheLimitAreLeftUnmarked() {
        let p = prepareZentaoDocHtml("<p>" + String(repeating: "a", count: zentaoFindLimit + 50) + "</p>", query: "a")
        XCTAssertEqual(p.matchCount, zentaoFindLimit)
    }

    func testAnEmptyBodyPreparesToNothing() {
        let p = prepareZentaoDocHtml("  ", query: "x")
        XCTAssertTrue(p.headings.isEmpty); XCTAssertEqual(p.matchCount, 0)
    }

    // MARK: blocks

    private func blocks(_ html: String, query: String = "") -> [ZentaoDocBlock] { ZentaoDocBlocks.build(prepareZentaoDocHtml(html, query: query).root) }

    func testHeadingsKeepTheirAnchorAndAreBold() {
        let b = blocks("<h2>Intro <em>now</em></h2><p>Hello <a href=\"/x\">link</a></p>")
        XCTAssertEqual(b.count, 2)
        guard case .text(let runs, let level, let anchor) = b[0] else { return XCTFail() }
        XCTAssertEqual(level, 2); XCTAssertEqual(anchor, 0)
        XCTAssertEqual(runs.map(\.text).joined(), "Intro now")
        XCTAssertTrue(runs.allSatisfy(\.bold)); XCTAssertTrue(runs[1].italic)
        guard case .text(let p, 0, nil) = b[1] else { return XCTFail() }
        XCTAssertEqual(p.last?.link, "/x")
    }

    func testFindMatchesBecomeRunsWithTheirIndexAndKeepTheirNeighboursStyle() {
        let b = blocks("<p>Token <b>token</b></p>", query: "token")
        guard case .text(let runs, _, _) = b[0] else { return XCTFail() }
        XCTAssertEqual(runs.map(\.find), [0, nil, 1])
        XCTAssertEqual(runs.map(\.text), ["Token", " ", "token"])
        XCTAssertTrue(runs[2].bold)
    }

    func testCodeBlocksKeepTheirTextWithoutTheTrailingNewlineAndTheirMatches() {
        let b = blocks("<pre><code>GET /a\nGET /b\n</code></pre>", query: "get")
        XCTAssertEqual(b, [.code("GET /a\nGET /b", matches: [ZentaoFindRange(index: 0, start: 0, end: 3), ZentaoFindRange(index: 1, start: 7, end: 10)])])
    }

    func testListsTablesQuotesImagesAndRulesBecomeBlocks() {
        let b = blocks("<ul><li>a</li><li>b<ul><li>c</li></ul></li></ul><table><tr><th>H</th></tr><tr><td>x</td></tr></table>"
                       + "<blockquote><p>q</p></blockquote><img src=\"/i.png\"><hr><ol start=\"3\"><li>z</li></ol>")
        guard case .list(false, 1, let items) = b[0] else { return XCTFail("\(b)") }
        XCTAssertEqual(items.count, 2)
        guard case .table(let rows) = b[1] else { return XCTFail() }
        XCTAssertEqual(rows.count, 2); XCTAssertTrue(rows[0][0].header); XCTAssertFalse(rows[1][0].header)
        guard case .text(let h, _, _) = rows[0][0].blocks[0] else { return XCTFail() }
        XCTAssertEqual(h.map(\.text).joined(), "H"); XCTAssertTrue(h[0].bold, "a header cell is bold")
        guard case .quote = b[2] else { return XCTFail() }
        XCTAssertEqual(b[3], .image(url: "/i.png")); XCTAssertEqual(b[4], .rule)
        guard case .list(true, 3, _) = b[5] else { return XCTFail() }
    }

    func testWhitespaceCollapsesOutsideCodeAndBreaksBecomeNewlines() {
        guard case .text(let runs, _, _) = blocks("<p>  a \n  b<br>c  </p>")[0] else { return XCTFail() }
        XCTAssertEqual(runs.map(\.text).joined(), "a b\nc")
    }

    func testLayoutNamesTheTopLevelBlockOfEachHeadingAndMatch() {
        let b = blocks("<h1>A</h1><p>zz</p><ul><li><p>zz</p></li></ul><h2>B</h2><pre>zz</pre>", query: "zz")
        let layout = ZentaoDocLayout(b)
        XCTAssertEqual(layout.blockOfHeading, [0: 0, 1: 3])
        XCTAssertEqual(layout.blockOfMatch, [0: 1, 1: 2, 2: 4])
        XCTAssertEqual(layout.anchorsOfBlock, [[0], [], [], [1], []])
    }

    // MARK: reader

    func testStepsWrapAroundTheMatches() {
        let r = ZentaoDocReader()
        r.layout = ZentaoDocLayout(blocks("<p>a</p><p>a</p><p>a</p>", query: "a"))
        r.resetMatches(3)
        XCTAssertEqual(r.current, 0)
        r.next(); r.next(); XCTAssertEqual(r.current, 2)
        r.next(); XCTAssertEqual(r.current, 0)
        r.previous(); XCTAssertEqual(r.current, 2)
        XCTAssertEqual(r.scrollRequest?.block, 2)
        XCTAssertEqual(r.scrollRequest?.anchor.y, 0.35)
    }

    func testWithoutMatchesNothingStepsOrScrolls() {
        let r = ZentaoDocReader()
        r.resetMatches(0)
        r.next(); r.previous(); r.revealCurrent()
        XCTAssertEqual(r.current, -1); XCTAssertNil(r.scrollRequest)
    }

    func testPickingAHeadingLightsItAtOnceAndScrollsThere() async throws {
        let r = ZentaoDocReader()
        r.layout = ZentaoDocLayout(blocks("<h1>A</h1><p>x</p><h2>B</h2>"))
        r.goToHeading(1)
        XCTAssertEqual(r.activeHeading, 1)
        XCTAssertEqual(r.scrollRequest?.block, 2); XCTAssertEqual(r.scrollRequest?.anchor, .top)
        // The page scrolling past other sections on the way must not light them up.
        r.track(tops: [0: -300, 1: 10], lead: 80)
        XCTAssertEqual(r.activeHeading, 1)
        try await Task.sleep(for: ZentaoDocReader.headingTrip + .milliseconds(150))
        r.track(tops: [0: -300, 1: 10], lead: 80)
        XCTAssertEqual(r.activeHeading, 1)
        r.track(tops: [0: 10, 1: 400], lead: 80)
        XCTAssertEqual(r.activeHeading, 0)
    }

    func testTheHeadingBeingReadIsTheLastOneAtOrAboveTheLead() {
        let tops: [Int: CGFloat] = [0: -500, 1: -20, 2: 60, 3: 700]
        XCTAssertEqual(ZentaoDocReader.activeHeading(tops: tops, lead: 80, atEnd: false, viewportHeight: 800), 2)
        // Before the first one is reached it stands in; at the very end the last one on screen counts.
        XCTAssertEqual(ZentaoDocReader.activeHeading(tops: [0: 300, 1: 600], lead: 80, atEnd: false, viewportHeight: 800), 0)
        XCTAssertEqual(ZentaoDocReader.activeHeading(tops: tops, lead: 80, atEnd: true, viewportHeight: 800), 3)
        XCTAssertEqual(ZentaoDocReader.activeHeading(tops: [:], lead: 80, atEnd: true, viewportHeight: 800), -1)
    }

    // MARK: file previews

    func testAFilePreviewsByItsNamesExtensionBeforeZenTaosOwn() {
        func kind(_ title: String, _ ext: String? = nil) -> ZentaoFilePreview {
            ZentaoFilePreview.of(TicketAttachment(id: "1", title: title, url: "/f", extension: ext))
        }
        XCTAssertEqual(kind("notes.md", "txt"), .markdown)
        XCTAssertEqual(kind("a.PNG"), .image)
        XCTAssertEqual(kind("run.sh"), .text)
        XCTAssertEqual(kind("blob", "json"), .text)
        XCTAssertEqual(kind("movie.mp4", "mp4"), .none)
        XCTAssertEqual(kind(".env"), .none)
    }

    // MARK: viewer helpers

    func testTheDocumentsWebUrlResolvesAgainstTheSite() {
        let a = Account(id: "a", workspaceId: "w", providerType: .zentao, handle: "h", baseUrl: "https://zt.example/zentao")
        XCTAssertEqual(ZentaoDocViewer.webUrl(account: a, docId: "12")?.absoluteString, "https://zt.example/zentao/doc-view-12.html")
        XCTAssertNil(ZentaoDocViewer.webUrl(account: Account(id: "a", workspaceId: "w", providerType: .zentao, handle: "h"), docId: "1"))
    }

    func testImageFallbackLinksResolveAgainstTheSiteRoot() throws {
        let a = Account(id: "a", workspaceId: "w", providerType: .zentao, handle: "h", baseUrl: "https://zt.example/zentao")
        let images = ZentaoDocImages(account: a, repo: FakeDocRepo())
        XCTAssertEqual(images.fallbackUrl("/zentao/file-read-1.png"), "https://zt.example/zentao/file-read-1.png")
        XCTAssertEqual(images.fallbackUrl("https://cdn.example/x.png"), "https://cdn.example/x.png")
    }

    func testTheReaderThemeFollowsTheAppUnlessForcedToTheOtherBrightness() {
        let light = AppTheme(settings: AppSettings())
        XCTAssertFalse(light.colors.isDark)
        XCTAssertEqual(ZentaoDocReaderTheme<EmptyView>.theme(app: light, forcedDark: nil, settings: AppSettings()).colors.isDark, false)
        XCTAssertEqual(ZentaoDocReaderTheme<EmptyView>.theme(app: light, forcedDark: false, settings: AppSettings()).colors.isDark, false)
        XCTAssertEqual(ZentaoDocReaderTheme<EmptyView>.theme(app: light, forcedDark: true, settings: AppSettings()).colors.isDark, true)
    }

    func testHistoryEntriesReadInTheAppsLanguageForTheActionsItKnows() {
        func entry(_ action: String, actor: String? = "ViPham") -> ZenTaoDocAction {
            ZenTaoDocAction(id: "1", action: action, summary: "ZenTao's own", actor: actor)
        }
        XCTAssertEqual(ZentaoDocHistoryEntry.sentence(entry("edited")), "ViPham edited it")
        XCTAssertEqual(ZentaoDocHistoryEntry.sentence(entry("opened")), "ViPham created it")
        XCTAssertEqual(ZentaoDocHistoryEntry.sentence(entry("releaseddoc")), "ViPham released it")
        XCTAssertEqual(ZentaoDocHistoryEntry.sentence(entry("weird")), "ZenTao's own")
        XCTAssertEqual(ZentaoDocHistoryEntry.sentence(entry("edited", actor: nil)), "ZenTao's own")
    }
}
