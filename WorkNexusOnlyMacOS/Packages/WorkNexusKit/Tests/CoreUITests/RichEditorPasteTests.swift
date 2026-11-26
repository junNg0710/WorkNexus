import AppKit
import XCTest
@testable import CoreUI

/// Pictures and files get into a description by paste.
@MainActor
final class RichEditorPasteTests: XCTestCase {
    private let paste = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")

    private func board() -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("wn-test-\(UUID().uuidString)"))
        pb.clearContents()
        return pb
    }

    private func png() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    /// With only a screenshot on the clipboard the text view said Paste did not apply, so Cmd-V never reached the editor.
    func testPasteIsOfferedForAPictureAndTheEditorTakesIt() async throws {
        let pb = board()
        defer { pb.releaseGlobally() }
        pb.setData(png(), forType: .png)
        let view = RichNSTextView()
        view.pasteboard = pb
        var pasted = 0
        view.onPasteImage = { pasted += 1; return true }
        XCTAssertTrue(view.validateMenuItem(paste))
        XCTAssertTrue(view.validateUserInterfaceItem(paste))
        view.paste(nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(pasted, 1)
        XCTAssertEqual(view.string, "")
    }

    func testFilesCopiedInFinderArePastedAsFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("paste_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("spec.pdf")
        try Data("%PDF".utf8).write(to: file)
        let pb = board()
        defer { pb.releaseGlobally() }
        pb.writeObjects([file as NSURL])
        let view = RichNSTextView()
        view.pasteboard = pb
        var got: [ClipboardAttachment] = []
        view.onFiles = { got += $0 }
        XCTAssertTrue(view.validateMenuItem(paste))
        XCTAssertTrue(view.validateUserInterfaceItem(paste))
        view.paste(nil)
        XCTAssertEqual(got.map(\.name), ["spec.pdf"])
        XCTAssertEqual(view.string, "", "the file's address is not typed in")
    }

    /// An editor that takes neither pictures nor files leaves Paste to the text view.
    func testAnEditorThatTakesNoFilesDoesNotOfferPasteForThem() {
        let pb = board()
        defer { pb.releaseGlobally() }
        pb.setData(png(), forType: .png)
        let view = RichNSTextView()
        view.pasteboard = pb
        XCTAssertEqual(view.validateMenuItem(paste), NSTextView().validateMenuItem(paste))
    }
}
