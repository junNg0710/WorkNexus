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

    /// A clock the test moves: every `tick` is one sprite frame later.
    private final class Clock { var date = Date(timeIntervalSince1970: 1_000_000) }
    private let clock = Clock()

    private func director(_ rolls: [Double] = []) -> PetDirector {
        var queue = rolls
        let clock = clock
        return PetDirector(random: { queue.isEmpty ? 0.5 : queue.removeFirst() }, now: { clock.date })
    }

    /// Ticks until `done`, at most `limit` frames.
    private func tick(_ d: PetDirector, limit: Int = 4000, until done: () -> Bool) {
        for _ in 0..<limit where !done() { clock.date += d.frameDuration; d.tick() }
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
        d.roomWidth = 900
        d.place(x: 0.9, y: 1)
        tick(d) { d.isWalking }
        XCTAssertEqual(d.animation, .runningLeft)         // the target is to its left
        let walk = try! XCTUnwrap(d.walk)
        XCTAssertEqual(walk.to, 0.1, accuracy: 0.001)
        // 0.8 of a 900 pt room at 90 pt/s: it takes 8 s whatever the window's width.
        XCTAssertEqual(walk.duration, 8, accuracy: 0.01)
        tick(d) { !d.isWalking }
        XCTAssertEqual(d.animation, .idle)
        XCTAssertNil(d.walk)
        XCTAssertEqual(d.x, 0.1, accuracy: 0.001)
    }

    /// Its place while walking is a smooth function of time: it never jumps, never goes back, eases out of the start and
    /// into the end, and is exactly at the target when the walk is over.
    func testAWalkGlidesFromStartToTarget() {
        let start = Date(timeIntervalSince1970: 0)
        let walk = PetDirector.Walk(from: 0.2, to: 0.8, start: start, duration: 4)
        XCTAssertEqual(walk.x(at: start), 0.2)
        XCTAssertEqual(walk.x(at: start + 2), 0.5, accuracy: 0.0001)
        XCTAssertEqual(walk.x(at: start + 4), 0.8, accuracy: 0.0001)
        XCTAssertEqual(walk.x(at: start + 99), 0.8)                       // and stays there
        XCTAssertEqual(walk.x(at: start - 1), 0.2)
        var last = 0.2, biggest = 0.0
        for i in 1...480 {                                               // 120 frames a second
            let x = walk.x(at: start + Double(i) / 120)
            XCTAssertGreaterThanOrEqual(x, last)
            biggest = max(biggest, x - last); last = x
        }
        XCTAssertLessThan(biggest, 0.002, "no frame moves it more than a hair")
        // It starts and ends slowly: the first and last tenth of a second cover less ground than one in the middle.
        let early = walk.x(at: start + 0.1) - 0.2, middle = walk.x(at: start + 2.05) - walk.x(at: start + 1.95)
        XCTAssertLessThan(early, middle / 4)
        XCTAssertFalse(walk.isOver(at: start + 3.9)); XCTAssertTrue(walk.isOver(at: start + 4))
    }

    func testPlacingOrPokingItMidWalkLeavesItWhereItHadGotTo() {
        let d = director([0.0, 0.5, 0.1, 0.1])
        d.roomWidth = 900
        d.place(x: 0.9, y: 1)
        tick(d) { d.isWalking }
        clock.date += 4                                                   // half way
        let midway = d.x(at: clock.date)
        XCTAssertEqual(midway, 0.5, accuracy: 0.01)
        d.poke()
        XCTAssertEqual(d.animation, .waving)
        XCTAssertNil(d.walk)
        XCTAssertEqual(d.x, midway, accuracy: 0.0001, "it does not jump back to where it set off, nor ahead to its target")
        d.place(x: 4, y: -2)
        XCTAssertEqual(d.x, 1); XCTAssertEqual(d.y, 0)
    }

    func testTheSheetCellOfAFrame() throws {
        let sheet = try XCTUnwrap(PetSpriteSheet(atlas: blankAtlas()))
        let first = sheet.unitRect(.idle, 0)
        XCTAssertEqual(first, CGRect(x: 0, y: 0, width: 1.0 / 8, height: 1.0 / 9))
        let waving = sheet.unitRect(.waving, 2)
        XCTAssertEqual(waving.minX, 2.0 / 8, accuracy: 1e-9); XCTAssertEqual(waving.minY, 3.0 / 9, accuracy: 1e-9)
        XCTAssertEqual(sheet.unitRect(.waving, 4), sheet.unitRect(.waving, 0))   // frames wrap
        // A layer counts rows from the bottom.
        XCTAssertEqual(PetSpriteLayer.layerRect(first).minY, 8.0 / 9, accuracy: 1e-9)
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
