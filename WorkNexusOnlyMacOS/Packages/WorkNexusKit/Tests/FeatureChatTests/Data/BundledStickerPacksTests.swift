import CoreDomain
import ImageIO
import XCTest
@testable import FeatureChat

/// The sticker packs that ship in the app (`App/Resources/Stickers/<pack>/`).
final class BundledStickerPacksTests: XCTestCase {
    private var stickersRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources/Stickers")
    }

    /// Hyper Rabbit (getstickerpack.com): 29 animated stickers, each a real animated image the chat can send.
    func testHyperRabbitIsInTheChatAsAnimatedStickers() async throws {
        let repo = LocalStickerRepository(bundleRoot: stickersRoot, directory: FileManager.default.temporaryDirectory.appendingPathComponent("st_\(UUID().uuidString)"))
        let all = try await repo.stickers().get()
        let rabbit = all.filter { $0.pack == "HyperRabbit" }
        XCTAssertEqual(rabbit.count, 29)
        XCTAssertEqual(rabbit.first?.name, "001.webp")
        XCTAssertFalse(rabbit.contains { $0.custom }, "a pack that ships with the app cannot be removed by the user")
        for s in rabbit {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: s.location) as CFURL, nil), s.name)
            XCTAssertGreaterThan(CGImageSourceGetCount(source), 1, "\(s.name) is not animated")
            let first = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(first.width, 256); XCTAssertEqual(first.height, 256)
            let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: s.location)[.size] as? Int)
            XCTAssertLessThan(size, 300_000, "\(s.name) is too heavy for a sticker")
        }
        // The other packs are still there.
        XCTAssertEqual(Set(all.map(\.pack)).isSuperset(of: ["Pepe", "PepeAnim", "WorkNexus"]), true)
    }

    /// The WorkNexus work stickers, with "Ko Cần Biết!", "Gửi cái tên ai làm", "Ko quan tâm" and "Thầy vô" (drawn for macOS
    /// first, upstream now) and "Có làm được không?" among them, drawn like the rest (256 × 256).
    func testTheWorkNexusPackHasTheMacOSOnlyStickers() async throws {
        let repo = LocalStickerRepository(bundleRoot: stickersRoot, directory: FileManager.default.temporaryDirectory.appendingPathComponent("st_\(UUID().uuidString)"))
        let pack = try await repo.stickers().get().filter { $0.pack == "WorkNexus" }
        XCTAssertEqual(pack.count, 17)
        for name in ["ko_can_biet.png", "gui_ten_ai_lam.png", "ko_quan_tam.png", "thay_vo.png", "co_lam_duoc_khong.png"] {
            let sticker = try XCTUnwrap(pack.first { $0.name == name }, name)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: sticker.location) as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 256); XCTAssertEqual(image.height, 256)
        }
    }

    /// Bundled stickers carry their set's tags (stickers.json): the emoji they stand for and, for some, words.
    func testBundledStickersCarryTheirSetsTags() async throws {
        let repo = LocalStickerRepository(bundleRoot: stickersRoot, directory: FileManager.default.temporaryDirectory.appendingPathComponent("st_\(UUID().uuidString)"))
        let all = try await repo.stickers().get()
        let thanks = try XCTUnwrap(all.first { $0.pack == "WorkNexus" && $0.name == "cam_on.png" })
        XCTAssertTrue(thanks.emoji.hasPrefix("🙏"))
        XCTAssertTrue(thanks.keywords.contains("cam on"))
        // Tagged by emoji alone.
        let laugh = try XCTUnwrap(all.first { $0.pack == "Pepe" && $0.name == "033.webp" })
        XCTAssertEqual(laugh.emoji, "😂🤣")
        XCTAssertTrue(laugh.keywords.isEmpty)
        XCTAssertTrue(all.contains { $0.pack == "PepeAnim" && !$0.emoji.isEmpty })
        // The tag files are not stickers.
        XCTAssertFalse(all.contains { $0.name == "stickers.json" })
    }

    /// Cute (getstickerpack.com): 21 still stickers, each a small image the chat can send; its source note is not one of them.
    func testCuteIsInTheChatAsStillStickers() async throws {
        let repo = LocalStickerRepository(bundleRoot: stickersRoot, directory: FileManager.default.temporaryDirectory.appendingPathComponent("st_\(UUID().uuidString)"))
        let cute = try await repo.stickers().get().filter { $0.pack == "Cute" }
        XCTAssertEqual(cute.map(\.name), (1...21).map { String(format: "%03d.webp", $0) })
        XCTAssertFalse(cute.contains { $0.custom })
        for s in cute {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: s.location) as CFURL, nil), s.name)
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), s.name)
            XCTAssertEqual(image.width, 256); XCTAssertEqual(image.height, 256)
            let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: s.location)[.size] as? Int)
            XCTAssertLessThan(size, 60_000, "\(s.name) is too heavy for a sticker")
        }
    }
}

/// Animated stickers really play: AppKit's `NSImage` sees the frames of a GIF only, so an animated WebP used to stand still.
@MainActor
final class AnimatedStickerPlaybackTests: XCTestCase {
    private var rabbit: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources/Stickers/HyperRabbit/001.webp")
    }
    private var gif: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/animated.gif") }

    /// How many different frames the view shows while it sits in a window for `seconds`.
    private func framesShown(_ data: Data, animated: Bool, seconds: Double = 1.2) async throws -> Int {
        let view = FramePlayerView(frame: NSRect(x: 0, y: 0, width: 120, height: 120))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.show(data, animated: animated)
        // Counted as changes of what the layer shows (a frame's memory may be used again, so identities alone undercount).
        var shown = 0
        var last: ObjectIdentifier?
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let c = view.layer?.contents {
                let id = ObjectIdentifier(c as AnyObject)
                if id != last { shown += 1; last = id }
            }
            try await Task.sleep(for: .milliseconds(15))
        }
        window.contentView = nil
        return shown
    }

    func testAnAnimatedWebpAndAGifBothPlay() async throws {
        let webp = try Data(contentsOf: rabbit), gifData = try Data(contentsOf: gif)
        XCTAssertTrue(StickerDecoder.isAnimated(webp)); XCTAssertTrue(StickerDecoder.isAnimated(gifData))
        let webpFrames = try await framesShown(webp, animated: true)
        XCTAssertGreaterThan(webpFrames, 3, "the animated WebP stood still")
        let gifFrames = try await framesShown(gifData, animated: true)
        XCTAssertGreaterThan(gifFrames, 3, "the GIF stood still")
    }

    func testNotAnimatedItStaysOnItsFirstFrameAndOutOfAWindowItDoesNotPlay() async throws {
        let webp = try Data(contentsOf: rabbit)
        let still = try await framesShown(webp, animated: false, seconds: 0.5)
        XCTAssertEqual(still, 1)
        let view = FramePlayerView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        view.show(webp, animated: true)
        XCTAssertFalse(view.isPlaying, "a sticker that is not on screen must not play")
        XCTAssertNotNil(view.layer?.contents)
    }

    /// Paused (the list scrolls), an animated picture holds the frame it is on instead of going back to its first one.
    func testPausedItHoldsItsFrameAndPlaysAgainWhenResumed() async throws {
        let webp = try Data(contentsOf: rabbit)
        let view = FramePlayerView(frame: NSRect(x: 0, y: 0, width: 120, height: 120))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        defer { window.contentView = nil }
        view.show(webp, animated: true)
        let first = view.layer?.contents as AnyObject?
        XCTAssertTrue(view.isPlaying)
        try await Task.sleep(for: .milliseconds(400))
        let reached = view.layer?.contents as AnyObject?
        XCTAssertFalse(reached === first, "it played")

        view.show(webp, animated: false)
        XCTAssertFalse(view.isPlaying)
        XCTAssertTrue((view.layer?.contents as AnyObject?) === reached, "pausing does not go back to the first frame")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue((view.layer?.contents as AnyObject?) === reached, "and nothing moves while paused")

        view.show(webp, animated: true)
        XCTAssertTrue(view.isPlaying)
    }

    func testAStillImageIsNotAnimated() {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        XCTAssertFalse(StickerDecoder.isAnimated(rep.representation(using: .png, properties: [:])!))
        XCTAssertFalse(StickerDecoder.isAnimated(Data("not an image".utf8)))
    }
}
