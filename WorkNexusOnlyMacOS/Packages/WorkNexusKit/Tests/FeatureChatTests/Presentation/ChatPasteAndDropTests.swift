import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import FeatureChat

/// Pictures and files get into the chat input by paste and by drop.
@MainActor
final class ChatPasteAndDropTests: XCTestCase {
    private func png(_ w: Int = 4, _ h: Int = 4) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    /// The input is plain text, which on its own enables Paste for text only: with a screenshot on the clipboard ⌘V did
    /// nothing. With files or a picture there, Paste is enabled and stages them.
    func testPasteIsOfferedForAPictureAndStagesIt() {
        let view = ComposerNSTextView()
        let paste = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        view.clipboardHasAttachments = { true }
        XCTAssertTrue(view.validateMenuItem(paste))
        XCTAssertTrue(view.validateUserInterfaceItem(paste))
        var staged = 0
        view.onPaste = { staged += 1; return true }
        view.paste(nil)
        XCTAssertEqual(staged, 1)
        XCTAssertEqual(view.string, "", "a staged picture types nothing into the input")
    }

    func testDroppedFilesAndPicturesBecomeFilesToSend() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("drop_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("spec.pdf"); try Data("%PDF".utf8).write(to: doc)
        let fromFinder = NSItemProvider(object: doc as NSURL)
        // A browser picture: PNG data, no file.
        let picture = NSItemProvider(item: png(8, 6) as NSData, typeIdentifier: UTType.png.identifier)
        picture.suggestedName = "cat.png"
        // A TIFF (as some apps drag a selection) goes as PNG.
        let tiff = NSItemProvider(item: NSImage(data: png(3, 3))!.tiffRepresentation! as NSData, typeIdentifier: UTType.tiff.identifier)
        let text = NSItemProvider(item: "hello" as NSString, typeIdentifier: UTType.plainText.identifier)
        let files = await ChatDrop.read([fromFinder, picture, tiff, text], now: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(files.map(\.name), ["spec.pdf", "cat.png", "dropped-2000-2.png"])
        XCTAssertEqual(files.map(\.mimeType), ["application/pdf", "image/png", "image/png"])
        XCTAssertEqual(files[0].data, Data("%PDF".utf8))
        XCTAssertEqual(NSBitmapImageRep(data: files[1].data)?.pixelsWide, 8)
        XCTAssertEqual(files[2].data.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    /// A folder dropped from Finder is skipped.
    func testADroppedFolderIsLeftOut() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("drop_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = await ChatDrop.read([NSItemProvider(object: dir as NSURL)])
        XCTAssertTrue(files.isEmpty)
    }
}
