import AppKit
import CoreDomain
import SwiftUI
import XCTest
@testable import CoreUI

/// The TBChat character: its sprite sheet, and what it does.
@MainActor
final class PetTests: XCTestCase {
    private func blankAtlas() -> CGImage {
        let w = PetSpriteSheet.columns * PetSpriteSheet.cellWidth, h = PetSpriteSheet.rows * PetSpriteSheet.cellHeight
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    func testTheSheetIsCutIntoTheFramesOfEachAnimation() throws {
        let sheet = try XCTUnwrap(PetSpriteSheet(atlas: blankAtlas()))
        for a in PetAnimation.allCases {
            XCTAssertEqual(sheet.frame(a, 0)?.width, 192)
            XCTAssertEqual(sheet.frame(a, 0)?.height, 208)
            // Frames wrap around, backwards too.
            XCTAssertNotNil(sheet.frame(a, a.frames + 3)); XCTAssertNotNil(sheet.frame(a, -1))
        }
        XCTAssertEqual(PetAnimation.allCases.reduce(0) { $0 + $1.frames }, 57)   // the 57 frames of the character
        XCTAssertEqual(Set(PetAnimation.allCases.map(\.row)).count, 9)
        let tooSmall = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        XCTAssertNil(PetSpriteSheet(atlas: tooSmall))
    }

    /// The sheet that ships with the app has a character in the cell of every frame and nothing in the unused cells.
    func testTheShippedSheetHasAFigureInEveryFrame() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources/Pet/tbchat-pet.png")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL, nil), "sheet missing at \(file.path)")
        let atlas = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(atlas.width, 1536); XCTAssertEqual(atlas.height, 1872)
        let sheet = try XCTUnwrap(PetSpriteSheet(atlas: atlas))
        for a in PetAnimation.allCases { for i in 0..<a.frames {
            XCTAssertGreaterThan(opaquePixels(try XCTUnwrap(sheet.frame(a, i))), 800, "\(a) frame \(i) is empty")
        } }
        // The cell after the last frame of a short row is empty.
        let rep = NSBitmapImageRep(cgImage: atlas)
        let unusedX = 7 * 192 + 96, row = PetAnimation.waving.row * 208 + 100
        XCTAssertEqual(rep.colorAt(x: unusedX, y: row)?.alphaComponent ?? 1, 0, accuracy: 0.01)
    }

    private func opaquePixels(_ image: CGImage) -> Int {
        let rep = NSBitmapImageRep(cgImage: image)
        var n = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 3) { for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
            if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { n += 1 }
        } }
        return n
    }

    // MARK: What it does

    private func director(_ rolls: [Double] = []) -> PetDirector {
        var queue = rolls
        return PetDirector(random: { queue.isEmpty ? 0.5 : queue.removeFirst() })
    }

    /// Ticks until `done`, at most `limit` frames.
    private func tick(_ d: PetDirector, limit: Int = 4000, until done: () -> Bool) {
        for _ in 0..<limit where !done() { d.tick() }
    }

    func testItIdlesAndLoopsItsFrames() {
        let d = director()
        XCTAssertEqual(d.animation, .idle)
        for _ in 0..<PetAnimation.idle.frames { d.tick() }
        XCTAssertEqual(d.frame, 0)
        XCTAssertEqual(d.animation, .idle)
    }

    func testAPokeWavesOnceAndGoesBackToIdling() {
        let d = director()
        d.poke()
        XCTAssertEqual(d.animation, .waving)
        for _ in 0..<PetAnimation.waving.frames { d.tick() }
        XCTAssertEqual(d.animation, .idle)
    }

    func testCelebratingJumpsTwice() {
        let d = director()
        d.celebrate()
        XCTAssertEqual(d.animation, .jumping)
        for _ in 0..<PetAnimation.jumping.frames { d.tick() }
        XCTAssertEqual(d.animation, .jumping)             // the second jump
        for _ in 0..<PetAnimation.jumping.frames { d.tick() }
        XCTAssertEqual(d.animation, .idle)
    }

    func testTheMoodSetsWhatItDoesWhenNothingElseGoesOn() {
        let d = director()
        d.mood = .busy;    XCTAssertEqual(d.animation, .running)
        d.mood = .offline; XCTAssertEqual(d.animation, .waiting)
        d.mood = .calm;    XCTAssertEqual(d.animation, .idle)
        d.mood = .trouble; XCTAssertEqual(d.animation, .failed)
        tick(d) { d.animation != .failed }
        XCTAssertEqual(d.animation, .idle)                // it shows the trouble twice, then settles
        // A gesture under way is finished before the new mood shows.
        d.poke(); d.mood = .busy
        XCTAssertEqual(d.animation, .waving)
        for _ in 0..<PetAnimation.waving.frames { d.tick() }
        XCTAssertEqual(d.animation, .running)
    }

    func testAfterAWhileIdlingItWalksSomewhereElseAndStopsThere() {
        // Rolls: the first wait, the next wait (set when it acts), then "walk" and where to.
        let d = director([0.0, 0.5, 0.1, 0.1])
        d.place(x: 0.9, y: 1)
        tick(d) { d.isWalking }
        XCTAssertEqual(d.animation, .runningLeft)         // the target is to its left
        let start = d.x
        tick(d) { !d.isWalking }
        XCTAssertEqual(d.animation, .idle)
        XCTAssertLessThan(d.x, start - 0.1)
        XCTAssertEqual(d.x, 0.1, accuracy: 0.001)
    }

    func testPlacingItStopsAWalkWhereItIs() {
        let d = director([0.0, 0.5, 0.1, 0.1])
        d.place(x: 0.9, y: 1)
        tick(d) { d.isWalking }
        d.place(x: 0.5, y: 0.7)
        XCTAssertFalse(d.isWalking)
        XCTAssertEqual(d.x, 0.5); XCTAssertEqual(d.y, 0.7)
        d.place(x: 4, y: -2)
        XCTAssertEqual(d.x, 1); XCTAssertEqual(d.y, 0)
    }

    func testReducedMotionKeepsItStill() {
        let d = director()
        d.reduceMotion = true
        d.poke(); d.celebrate(); d.mood = .busy
        XCTAssertEqual(d.animation, .idle)
        d.tick()
        XCTAssertEqual(d.frame, 0)
    }
}

/// Renders the character in a room, in a few moods (`/tmp/wn-pet-render/pet.png`).
@MainActor
final class PetRenderTests: XCTestCase {
    func testTheCharacterIsDrawnInItsRoom() async throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources/Pet/tbchat-pet.png")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL, nil))
        let sheet = try XCTUnwrap(PetSpriteSheet(atlas: try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))))
        func room(_ configure: (PetDirector) -> Void) -> some View {
            let d = PetDirector(); configure(d); d.x = 0.5
            return PetView(director: d, sheet: sheet).frame(width: 220, height: 160).background(Color(white: 0.93))
        }
        let view = HStack(spacing: 8) {
            room { _ in }
            room { $0.poke() }
            room { $0.mood = .busy }
            room { $0.mood = .trouble }
            room { $0.mood = .offline }
        }.padding(8)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1156, height: 176)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try FileManager.default.createDirectory(atPath: "/tmp/wn-pet-render", withIntermediateDirectories: true)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/wn-pet-render/pet.png"))
        XCTAssertGreaterThan(png.count, 5_000)
    }
}
