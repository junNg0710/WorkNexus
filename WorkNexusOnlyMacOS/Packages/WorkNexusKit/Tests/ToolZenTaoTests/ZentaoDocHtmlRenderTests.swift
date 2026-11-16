import AppKit
import CoreDomain
import CoreUI
import SwiftUI
import XCTest
@testable import ToolZenTao

/// Renders the document body with the HTML features the reader draws (colours, scripts, alignment, spans, blocks in
/// cells) off-screen to `/tmp/wn-zt2-render/*.png`, for looking at.
@MainActor
final class ZentaoDocHtmlRenderTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/wn-zt2-render")
    private let account = Account(id: "a1", workspaceId: "w1", providerType: .zentao, handle: "thanh", baseUrl: "https://zt.example/zentao")

    private func render<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false, wait: Double = 0.7) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var settings = AppSettings(); if dark { settings.variant = .dark }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.environment(\.appTheme, theme).frame(width: size.width, height: size.height)
            .background(theme.colors.card).environment(\.colorScheme, theme.colorScheme))
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

    private let html = """
    <h1 style="text-align:center">Release notes</h1>
    <p>Water is H<sub>2</sub>O, and E = mc<sup>2</sup>. Colours: <font color="#e60000">red text</font>,
    <span style="color:#0066cc">blue</span>, <span style="background-color:#ffff00">highlighted</span> and <a href="https://example.com">a link</a>.</p>
    <p style="text-align:right">Right aligned paragraph.</p>
    <table>
      <tr><th colspan="3" style="text-align:center">Quarterly results</th></tr>
      <tr><th>Region</th><th>Details</th><th>Score</th></tr>
      <tr><td rowspan="2">North</td><td><p>First paragraph of a long cell that has to wrap onto several lines to show wrapping.</p><p>Second paragraph.</p></td><td style="text-align:right" bgcolor="#e8f5e9">92</td></tr>
      <tr><td><ul><li>point one</li><li>point two</li></ul></td><td><img src="/file-read-1.png"></td></tr>
      <tr><td>South</td><td colspan="2">Spans two columns with <b>bold</b> and <code>code</code>.</td></tr>
    </table>
    <p>After the table.</p>
    """

    func testTheBodyWithTablesColoursAndAlignment() throws {
        let prepared = prepareZentaoDocHtml(html, query: "")
        let blocks = ZentaoDocBlocks.build(prepared.root)
        let view = ScrollView {
            ZentaoDocBlockList(blocks: blocks, reader: ZentaoDocReader(), images: ZentaoDocImages(account: account, repo: FakeDocRepo()))
                .padding(24)
        }
        try render("doc-html-light", view, size: CGSize(width: 820, height: 760))
        try render("doc-html-dark", view, size: CGSize(width: 820, height: 760), dark: true)
        try render("doc-html-narrow", view, size: CGSize(width: 420, height: 900))
    }
}
