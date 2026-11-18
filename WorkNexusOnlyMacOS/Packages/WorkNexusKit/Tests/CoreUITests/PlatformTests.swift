import AVFoundation
import AppKit
import XCTest
@testable import CoreUI

private func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("platform_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private func pngData(width: Int, height: Int, color: NSColor = .red) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    color.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

final class DockBadgeTests: XCTestCase {
    func testLabel() {
        XCTAssertEqual(DockBadge.label(0), "")
        XCTAssertEqual(DockBadge.label(-3), "")
        XCTAssertEqual(DockBadge.label(7), "7")
        XCTAssertEqual(DockBadge.label(99), "99")
        XCTAssertEqual(DockBadge.label(100), "99+")
    }
}

final class WindowPlacementStoreTests: XCTestCase {
    func testDefaultsToMaximizedThenRemembers() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = WindowPlacementStore(directory: dir)
        XCTAssertTrue(store.readMaximized())
        store.writeMaximized(false)
        XCTAssertFalse(store.readMaximized())
        store.write(WindowPlacement(maximized: false, frame: CGRect(x: 10, y: 20, width: 800, height: 600)))
        XCTAssertEqual(store.read().frame, CGRect(x: 10, y: 20, width: 800, height: 600))
        store.writeMaximized(true)
        XCTAssertTrue(store.readMaximized())
        XCTAssertEqual(store.read().frame?.width, 800)   // the frame survives a maximize toggle
    }

    func testUnreadableFileMeansMaximized() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try "not json".write(to: dir.appendingPathComponent(WindowPlacementStore.fileName), atomically: true, encoding: .utf8)
        XCTAssertTrue(WindowPlacementStore(directory: dir).readMaximized())
    }
}

@MainActor
final class AppNameServiceTests: XCTestCase {
    func testRenameCurrentAndReset() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        var title: String?; var tip: String??
        let svc = AppNameService(file: dir.appendingPathComponent("sub/app_name.txt"), setTrayToolTip: { tip = .some($0) }, setWindowTitle: { title = $0 })
        XCTAssertNil(svc.current())
        XCTAssertTrue(svc.rename("  My Hub  "))
        XCTAssertEqual(svc.current(), "My Hub")
        XCTAssertEqual(title, "My Hub")
        XCTAssertEqual(tip, .some("My Hub"))
        XCTAssertTrue(svc.rename("   "))
        XCTAssertNil(svc.current())
        XCTAssertEqual(title, AppIdentity.appName)
    }

    func testLongNameIsTruncated() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let svc = AppNameService(file: dir.appendingPathComponent("n.txt"), setWindowTitle: { _ in })
        svc.rename(String(repeating: "a", count: 90))
        XCTAssertEqual(svc.current()?.count, AppNameService.maxLength)
    }
}

@MainActor
final class AppIconServiceTests: XCTestCase {
    func testChooseCropsToSquareAndResetRemoves() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("wide.png")
        try pngData(width: 600, height: 300).write(to: src)
        var applied: [Bool] = []
        let svc = AppIconService(folder: dir.appendingPathComponent("icons"), onApply: { applied.append($0 != nil) })
        XCTAssertNil(svc.current())
        XCTAssertTrue(svc.choose(src))
        let kept = try XCTUnwrap(svc.current())
        let rep = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: kept)))
        XCTAssertEqual(rep.pixelsWide, AppIconService.side)
        XCTAssertEqual(rep.pixelsHigh, AppIconService.side)
        svc.reset()
        XCTAssertNil(svc.current())
        XCTAssertEqual(applied, [true, false])
    }

    func testNonImageIsRefusedAndKeepsCurrent() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let bad = dir.appendingPathComponent("x.png"); try Data([1, 2, 3]).write(to: bad)
        let svc = AppIconService(folder: dir.appendingPathComponent("icons"))
        XCTAssertFalse(svc.choose(bad))
        XCTAssertNil(svc.current())
    }
}

final class PasteboardKitTests: XCTestCase {
    private func board() -> NSPasteboard { NSPasteboard(name: NSPasteboard.Name("wn.test.\(UUID().uuidString)")) }

    func testImageRoundTrip() {
        let pb = board(); defer { pb.releaseGlobally() }
        let kit = PasteboardKit(pasteboard: pb)
        XCTAssertNil(kit.readImage())
        let png = pngData(width: 8, height: 8)
        kit.copyImage(png)
        XCTAssertEqual(kit.readImage(), png)
    }

    func testCopiedFilesWinOverImageData() throws {
        let pb = board(); defer { pb.releaseGlobally() }
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("note.txt"); try "hi".write(to: file, atomically: true, encoding: .utf8)
        pb.clearContents()
        pb.writeObjects([file as NSURL])
        pb.setData(pngData(width: 4, height: 4), forType: .png)    // a screenshot-style payload beside the file
        let got = try XCTUnwrap(PasteboardKit(pasteboard: pb).readAttachments())
        XCTAssertEqual(got, [ClipboardAttachment(name: "note.txt", data: Data("hi".utf8))])
    }

    func testImageOnlyBecomesPastedPng() throws {
        let pb = board(); defer { pb.releaseGlobally() }
        let kit = PasteboardKit(pasteboard: pb)
        kit.copyImage(pngData(width: 4, height: 4))
        let got = try XCTUnwrap(kit.readAttachments(now: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(got.first?.name, "pasted-1000.png")
    }

    func testTextOnlyIsNil() {
        let pb = board(); defer { pb.releaseGlobally() }
        pb.clearContents(); pb.setString("just text", forType: .string)
        XCTAssertNil(PasteboardKit(pasteboard: pb).readAttachments())
        XCTAssertFalse(PasteboardKit(pasteboard: pb).hasAttachments())
    }

    /// What a screenshot to the clipboard leaves (an image, no text) is an attachment, in TIFF as in PNG.
    func testAScreenshotOnTheClipboardIsAnAttachment() throws {
        let pb = board(); defer { pb.releaseGlobally() }
        let kit = PasteboardKit(pasteboard: pb)
        XCTAssertFalse(kit.hasAttachments())
        let tiff = try XCTUnwrap(NSImage(data: pngData(width: 6, height: 4))?.tiffRepresentation)
        pb.clearContents(); pb.setData(tiff, forType: .tiff)
        XCTAssertTrue(kit.hasAttachments())
        let png = try XCTUnwrap(kit.readImage())
        XCTAssertEqual(NSBitmapImageRep(data: png)?.pixelsWide, 6)
        XCTAssertEqual(png.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]), "read back as PNG")
    }

    /// A JPEG on its own (as some apps copy a picture) is pasted as a picture.
    func testAnImageInAnotherFormatIsAnAttachment() throws {
        let pb = board(); defer { pb.releaseGlobally() }
        let rep = try XCTUnwrap(NSBitmapImageRep(data: pngData(width: 5, height: 5)))
        let jpeg = try XCTUnwrap(rep.representation(using: .jpeg, properties: [:]))
        let kit = PasteboardKit(pasteboard: pb)
        pb.clearContents(); pb.setData(jpeg, forType: NSPasteboard.PasteboardType("public.jpeg"))
        XCTAssertTrue(kit.hasAttachments())
        XCTAssertEqual(try XCTUnwrap(kit.readAttachments()).first.flatMap { NSBitmapImageRep(data: $0.data)?.pixelsWide }, 5)
    }
}

@MainActor
final class AppResumeCounterTests: XCTestCase {
    func testResumesWithinGapAreIgnored() {
        let center = NotificationCenter()
        let name = Notification.Name("resume")
        var clock = Date(timeIntervalSince1970: 0)
        let counter = AppResumeCounter(minGap: 10, center: center, name: name, now: { clock })
        center.post(name: name, object: nil); XCTAssertEqual(counter.count, 1)
        clock = Date(timeIntervalSince1970: 5); center.post(name: name, object: nil); XCTAssertEqual(counter.count, 1)
        clock = Date(timeIntervalSince1970: 11); center.post(name: name, object: nil); XCTAssertEqual(counter.count, 2)
    }
}

@MainActor
final class LinkRouterTests: XCTestCase {
    private final class Handler: LinkHandler {
        var seen: [String] = []; let opens: Bool
        init(opens: Bool) { self.opens = opens }
        func handle(_ url: String) -> Bool { seen.append(url); return opens }
    }

    func testStagesAskedInOrderUntilOneOpens() {
        let r = LinkRouter(); let app = Handler(opens: false), mini = Handler(opens: true)
        r.register(.app, app); r.register(.miniApp, mini)
        XCTAssertTrue(r.route("https://a"))
        XCTAssertEqual(app.seen, ["https://a"]); XCTAssertEqual(mini.seen, ["https://a"])
        XCTAssertTrue(r.route("https://b", skip: [.app]))
        XCTAssertEqual(app.seen, ["https://a"])
    }

    func testUnregisterOnlyRemovesTheCurrentHandler() {
        let r = LinkRouter(); let old = Handler(opens: true), new = Handler(opens: true)
        r.register(.app, old); r.register(.app, new)
        r.unregister(.app, old)
        XCTAssertTrue(r.route("https://x")); XCTAssertEqual(new.seen.count, 1)
        r.unregister(.app, new)
        XCTAssertFalse(r.route("https://x"))
    }
}

final class VideoThumbnailerTests: XCTestCase {
    func testConcurrentRequestsShareOneRunAndUseTheCachedFrame() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let video = dir.appendingPathComponent("1_clip.mp4"); try Data([0]).write(to: video)
        let frame = Data([1, 2, 3])
        try frame.write(to: URL(fileURLWithPath: video.path + ".thumb.png"))
        let t = VideoThumbnailer()
        async let a = t.thumbnail(of: video.path)
        async let b = t.thumbnail(of: video.path)
        let (first, second) = await (a, b)
        XCTAssertEqual(first, frame); XCTAssertEqual(second, frame)
        XCTAssertEqual(t.cachedThumbnail(of: video.path), frame)
    }

    func testUndecodableVideoYieldsNilNotACrash() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let video = dir.appendingPathComponent("broken.mp4"); try Data([0, 1, 2]).write(to: video)
        let result = await VideoThumbnailer().thumbnail(of: video.path)
        XCTAssertNil(result)
    }

    func testRealVideoGetsAFrame() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let video = dir.appendingPathComponent("real.mov")
        try await Self.writeVideo(to: video)
        let png = await VideoThumbnailer().thumbnail(of: video.path)
        let data = try XCTUnwrap(png)
        XCTAssertNotNil(NSBitmapImageRep(data: data))
        XCTAssertTrue(FileManager.default.fileExists(atPath: video.path + ".thumb.png"))
    }

    private static func writeVideo(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        for i in 0..<10 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer)
            adaptor.append(buffer!, withPresentationTime: CMTime(value: Int64(i), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}

final class DesktopNotifierTests: XCTestCase {
    /// `UNUserNotificationCenter.current()` traps outside an app bundle: the notifier must say "unavailable" instead.
    func testIsUnavailableOutsideAnAppBundleAndNeverTraps() async {
        let n = DesktopNotifier()
        let ok = await n.initialize()
        XCTAssertFalse(ok)
        let granted = await n.permissionGranted()
        XCTAssertNil(granted)
        let requested = await n.requestPermission()
        XCTAssertFalse(requested)
        await n.show(id: 1, title: "t", body: "b", payload: "p")     // no-ops
        var it = n.taps.makeAsyncIterator()
        let tap = Task { await it.next() }
        try? await Task.sleep(for: .milliseconds(20)); tap.cancel()
    }

    @MainActor func testTheTrayMenuCanHoldAnOnOffItem() {
        let tray = StatusItemService(strings: StatusItemStrings(openApp: "Open", quitApp: "Quit"))
        XCTAssertEqual(tray.menuTitles, ["Open", "-", "Quit"])
        var toggled = 0
        tray.setToggle(StatusItemToggle(title: "Hide the pet", systemImage: "pawprint") { toggled += 1 })
        XCTAssertEqual(tray.menuTitles, ["Open", "Hide the pet", "-", "Quit"])
        tray.setToggle(nil)
        XCTAssertEqual(tray.menuTitles, ["Open", "-", "Quit"])
        XCTAssertEqual(toggled, 0)
    }

    func testStatusItemStringsDefaultToTheLocalizedTrayLabels() {
        let s = StatusItemStrings()
        XCTAssertFalse(s.openApp.isEmpty); XCTAssertFalse(s.quitApp.isEmpty)
        XCTAssertEqual(StatusItemStrings(openApp: "A", quitApp: "B"), StatusItemStrings(openApp: "A", quitApp: "B"))
    }
}
