import AppKit
import CoreDomain
import CoreUI
import SwiftUI
import XCTest
@testable import ToolZenTao

/// Renders the Docs views off-screen so layout crashes show up in `swift test` and the PNGs can be eyeballed
/// (`/tmp/wn-zt-docs-render/*.png`). Asserts only that something non-blank was drawn.
@MainActor
final class ZentaoDocsRenderTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/wn-zt-docs-render")
    private let account = Account(id: "a1", workspaceId: "w1", providerType: .zentao, handle: "thanh", baseUrl: "https://zt.example/zentao")

    private func render<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false, wait: Double = 0.7) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var settings = AppSettings(); if dark { settings.variant = .dark }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.environment(\.appTheme, theme).frame(width: size.width, height: size.height)
            .background(theme.colors.bg).environment(\.colorScheme, theme.colorScheme))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: outDir.appendingPathComponent("\(name).png"))
        XCTAssertGreaterThan(png.count, 2_000, "\(name) rendered blank")
    }

    private let body = """
    <h1>Wallet API</h1><p>The <b>wallet</b> service signs <i>transactions</i>. See <a href="https://example.com">the guide</a> and call <code>POST /sign</code>.</p>
    <h2>Authentication</h2><ul><li>Send a token</li><li>Refresh it<ul><li>every hour</li></ul></li></ul>
    <pre><code>curl -X POST /sign \\
      -H "Authorization: token"
    {"ok": true}</code></pre>
    <h2>Errors</h2><table><tr><th>Code</th><th>Meaning</th></tr><tr><td>401</td><td>Bad token</td></tr></table>
    <blockquote><p>Tokens expire.</p></blockquote><h3>Image</h3><img src="/file-read-1.png"><hr><p>The end.</p>
    """

    private func doc() -> ZenTaoDoc {
        ZenTaoDoc(id: "5", title: "Wallet API reference", libId: "9", html: body, version: 3,
                  author: ZenTaoDocPerson(account: "vipham", name: "ViPham"), editors: [ZenTaoDocPerson(account: "thanh", name: "Thanh"), ZenTaoDocPerson(account: "cat")],
                  views: 42, addedDate: Date(timeIntervalSince1970: 1_760_000_000), editedDate: Date(timeIntervalSince1970: 1_762_000_000),
                  files: [TicketAttachment(id: "f1", title: "design.pdf", url: "/f1", size: 52_000, addedBy: "thanh")])
    }

    private func state(_ d: ZenTaoDoc?) -> ZentaoDocsState {
        let repo = FakeDocRepo(); repo.doc = d
        repo.history = [ZenTaoDocAction(id: "1", action: "created", summary: "s", date: Date(timeIntervalSince1970: 1_760_000_000), actor: "ViPham"),
                        ZenTaoDocAction(id: "2", action: "edited", summary: "s", date: Date(timeIntervalSince1970: 1_762_000_000), actor: "Thanh",
                                        changes: [ZenTaoDocChange(field: "Title", from: "Wallet", to: "Wallet API")])]
        return ZentaoDocsState(repo: repo)
    }

    func testTheDocumentViewerOnLightAndDark() throws {
        let s = state(doc())
        try render("viewer-light", ZentaoDocViewer(docs: s, account: account, docId: "5"), size: CGSize(width: 1200, height: 800))
        try render("viewer-dark", ZentaoDocViewer(docs: s, account: account, docId: "5"), size: CGSize(width: 1200, height: 800), dark: true)
        // Narrow: the outline moves behind a button.
        try render("viewer-narrow", ZentaoDocViewer(docs: s, account: account, docId: "5"), size: CGSize(width: 700, height: 700))
    }

    func testTheViewerReadsOnTheOtherBrightnessWhenForced() throws {
        let s = state(doc())
        s.toggleReaderBrightness(currentDark: false, appDark: false)
        XCTAssertEqual(s.readerForcedDark, true)
        try render("viewer-forced-dark", ZentaoDocViewer(docs: s, account: account, docId: "5"), size: CGSize(width: 1000, height: 600))
    }

    func testAnAttachmentOnlyDocumentAndAMissingOne() throws {
        let attachment = ZenTaoDoc(id: "6", title: "Spec.pdf", libId: "9", html: "", isAttachment: true,
                                   files: [TicketAttachment(id: "f2", title: "spec.pdf", url: "/f2", size: 1_000)])
        try render("viewer-attachment", ZentaoDocViewer(docs: state(attachment), account: account, docId: "6"), size: CGSize(width: 900, height: 500))
        try render("viewer-missing", ZentaoDocViewer(docs: state(nil), account: account, docId: "7"), size: CGSize(width: 900, height: 500))
    }

    func testTheFindBarAndTheHistoryAndTheTreeRows() throws {
        let s = state(doc())
        try render("find-bar", ZentaoDocFindBar(reader: ZentaoDocReader(), query: "token", onQuery: { _ in }, onClose: {}).padding(), size: CGSize(width: 560, height: 80))
        try render("history", ZentaoDocHistoryPanel(docs: s, account: account, docId: "5", onClose: {}).frame(width: 480, height: 420), size: CGSize(width: 480, height: 420))
        let pins = ZenTaoDocPins()
        try render("tree", VStack(alignment: .leading, spacing: 0) {
            ZentaoDocLibNode(docs: s, account: account, lib: ZenTaoDocLib(id: "9", name: "Wallet"), pins: pins)
            ZentaoDocRow(docs: s, account: account, doc: ZenTaoDocSummary(id: "5", title: "Wallet API reference", libId: "9"), pins: pins, selected: true, libraryName: "Wallet")
            ZentaoDocRow(docs: s, account: account, doc: ZenTaoDocSummary(id: "6", title: "Private notes", libId: "9", acl: "private"), pins: pins, selected: false)
        }.frame(width: 300).padding(), size: CGSize(width: 340, height: 200))
    }

    func testMatchesInEveryKindOfBlockAreMarkedAndLaidOut() {
        let p = prepareZentaoDocHtml(body, query: "token")
        XCTAssertEqual(p.matchCount, 4)
        let layout = ZentaoDocLayout(ZentaoDocBlocks.build(p.root))
        XCTAssertEqual(layout.blockOfMatch.count, 4)
    }
}
