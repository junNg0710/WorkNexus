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
        d.mood = .offline; XCTAssertEqual(d.animation, .idle)       // dimmed by the view, not animated
        d.mood = .attention; XCTAssertEqual(d.animation, .waiting)
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

    func testANotificationWavesTwiceAndAFinishedJobIsLookedOver() {
        let d = director()
        d.notify()
        XCTAssertEqual(d.animation, .waving)
        for _ in 0..<PetAnimation.waving.frames { d.tick() }
        XCTAssertEqual(d.animation, .waving)
        for _ in 0..<PetAnimation.waving.frames { d.tick() }
        XCTAssertEqual(d.animation, .idle)
        d.done()
        XCTAssertEqual(d.animation, .review)
        d.notify(); d.done()                              // a finished job does not cut a wave short
        XCTAssertEqual(d.animation, .waving)
    }

    func testItDoesNotWanderInARoomAsSmallAsItself() {
        let d = director([0.0, 0.5, 0.1, 0.1])
        d.canWander = false
        tick(d, limit: 2000) { d.isWalking }
        XCTAssertFalse(d.isWalking)
    }

    func testCodexTimingHoldsTheLastFrameLonger() {
        XCTAssertEqual(PetTiming.codex.duration(.idle, frame: 0), 0.28, accuracy: 1e-9)
        XCTAssertEqual(PetTiming.codex.duration(.idle, frame: 5), 0.32, accuracy: 1e-9)
        XCTAssertEqual(PetTiming.codex.duration(.idle, frame: 6), 0.28, accuracy: 1e-9)   // wraps
        for a in PetAnimation.allCases { XCTAssertEqual(PetTiming.codexMilliseconds(a).count, a.frames, "\(a)") }
        XCTAssertEqual(PetTiming.steady.duration(.running, frame: 3), PetAnimation.running.frameDuration)
        let d = director()
        d.timing = .codex
        XCTAssertEqual(d.frameDuration, 0.28, accuracy: 1e-9)
        d.tick()
        XCTAssertEqual(d.frameDuration, 0.11, accuracy: 1e-9)
    }

    private func atlas(rows: Int) -> CGImage {
        CGContext(data: nil, width: 8 * 192, height: rows * 208, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    func testAV2SheetCanLookInSixteenDirections() throws {
        let v1 = try XCTUnwrap(PetSpriteSheet(atlas: atlas(rows: 9)))
        XCTAssertEqual(v1.version, .v1); XCTAssertFalse(v1.canLook)
        XCTAssertNil(v1.lookUnitRect(0)); XCTAssertNil(v1.neutralLookUnitRect)
        let v2 = try XCTUnwrap(PetSpriteSheet(atlas: atlas(rows: 11)))
        XCTAssertEqual(v2.version, .v2); XCTAssertTrue(v2.canLook)
        XCTAssertEqual(v2.unitRect(.idle, 0), CGRect(x: 0, y: 0, width: 1.0 / 8, height: 1.0 / 11))
        let up = try XCTUnwrap(v2.lookUnitRect(0)), left = try XCTUnwrap(v2.lookUnitRect(12))
        XCTAssertEqual(up.minY, 9.0 / 11, accuracy: 1e-9); XCTAssertEqual(up.minX, 0)
        XCTAssertEqual(left.minY, 10.0 / 11, accuracy: 1e-9); XCTAssertEqual(left.minX, 4.0 / 8, accuracy: 1e-9)
        XCTAssertEqual(v2.lookUnitRect(16), up)                                             // wraps
        XCTAssertEqual(try XCTUnwrap(v2.neutralLookUnitRect).minX, 6.0 / 8, accuracy: 1e-9)
    }

    func testTheDirectionToThePointerCountsClockwiseFromUp() {
        XCTAssertEqual(PetSpriteSheet.lookDirection(dx: 0, dy: -10), 0)     // up
        XCTAssertEqual(PetSpriteSheet.lookDirection(dx: 10, dy: 0), 4)      // right
        XCTAssertEqual(PetSpriteSheet.lookDirection(dx: 0, dy: 10), 8)      // down
        XCTAssertEqual(PetSpriteSheet.lookDirection(dx: -10, dy: 0), 12)    // left
        XCTAssertEqual(PetSpriteSheet.lookDirection(dx: 10, dy: -10), 2)    // up-right
        // On screen y counts up: a pointer above the pet is "up"; too far or right on it, it looks nowhere.
        XCTAssertEqual(PetGazeTracker.direction(from: .zero, to: NSPoint(x: 0, y: 100)), 0)
        XCTAssertNil(PetGazeTracker.direction(from: .zero, to: NSPoint(x: 5, y: 5)))
        XCTAssertNil(PetGazeTracker.direction(from: .zero, to: NSPoint(x: 5000, y: 0)))
        let d = director()
        d.gaze = 4
        XCTAssertTrue(d.showsGaze)
        d.poke()
        XCTAssertFalse(d.showsGaze)                                         // a gesture plays its own frames
    }

    func testWhatItSaysStaysAWhileAndThePointerShowsTheState() {
        let d = director()
        d.status = "All quiet"
        XCTAssertNil(d.bubble(hovering: false))
        XCTAssertEqual(d.bubble(hovering: true), "All quiet")
        d.say("New chat message", for: 2)
        XCTAssertEqual(d.bubble(hovering: false), "New chat message")
        XCTAssertEqual(d.bubble(hovering: true), "All quiet")          // the pointer asks for the whole picture
        clock.date += 1; d.tick()
        XCTAssertNotNil(d.speech)
        clock.date += 1.5; d.tick()
        XCTAssertNil(d.speech)                                          // said its line, then quiet again
        d.reduceMotion = true
        d.say("Sync failed")
        XCTAssertEqual(d.bubble(hovering: false), "Sync failed")        // still says it, standing still
    }

    func testItWalksAboutInAnyMoodButOnlyGesturesWhenCalm() {
        // Waiting for the user: after a while it still walks to another spot, then goes back to waiting.
        let d = director([0.0, 0.5, 0.1, 0.1])
        d.roomWidth = 900
        d.place(x: 0.9, y: 1)
        d.mood = .attention
        XCTAssertEqual(d.animation, .waiting)
        tick(d) { d.isWalking }
        XCTAssertTrue(d.isWalking)
        tick(d) { !d.isWalking }
        XCTAssertEqual(d.animation, .waiting)
        // Without room to walk, a pet that is not calm keeps its mood instead of waving out of the blue.
        let still = director([0.0, 0.5, 0.9, 0.1])
        still.canWander = false
        still.mood = .busy
        var gestured = false
        tick(still, limit: 600) { gestured = still.animation.isGesture; return gestured }
        XCTAssertFalse(gestured)
        XCTAssertEqual(still.animation, .running)
    }

    func testItWandersWithinHalfAMinute() {
        let d = director()
        d.roomWidth = 900
        let start = clock.date
        tick(d) { d.isWalking || d.animation.isGesture }
        XCTAssertTrue(d.isWalking)
        XCTAssertLessThanOrEqual(clock.date.timeIntervalSince(start), 21)   // 8-20 s of standing about, then a walk
    }

    func testTheBubbleStaysInsideTheRoom() {
        // In the middle of a wide room: right above the pet.
        XCTAssertEqual(PetView.bubbleShift(petLeft: 400, petWidth: 84, roomWidth: 1000), 0)
        // Against the right edge: moved left so its right side meets the edge.
        let shift = PetView.bubbleShift(petLeft: 916, petWidth: 84, roomWidth: 1000)
        XCTAssertEqual(916 + 42 - PetSpeechBubble.maxWidth / 2 + shift + PetSpeechBubble.maxWidth, 1000, accuracy: 0.001)
        // Against the left edge: moved right.
        XCTAssertGreaterThan(PetView.bubbleShift(petLeft: 0, petWidth: 84, roomWidth: 1000), 0)
    }

    func testThePointerIsTakenOnlyOverThePet() {
        let d = director()
        d.place(x: 0.5, y: 1)
        let rect = PetView.spriteRect(director: d, room: CGSize(width: 1084, height: 591), width: 84)
        XCTAssertEqual(rect, CGRect(x: 500, y: 500, width: 84, height: 91))   // the middle of the bottom
        XCTAssertFalse(PetStageHostingView<Color>.takesPointer(at: NSPoint(x: 100, y: 100), petRect: rect))   // content under it
        XCTAssertTrue(PetStageHostingView<Color>.takesPointer(at: NSPoint(x: 540, y: 540), petRect: rect))     // the pet itself
        XCTAssertFalse(PetStageHostingView<Color>.takesPointer(at: NSPoint(x: 540, y: 540), petRect: nil))     // no pet shown
        let host = PetStageHostingView(rootView: Color.clear)
        host.frame = NSRect(x: 0, y: 0, width: 1084, height: 591)
        host.petRect = { _ in rect }
        XCTAssertNil(host.hitTest(NSPoint(x: 100, y: 100)))
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
