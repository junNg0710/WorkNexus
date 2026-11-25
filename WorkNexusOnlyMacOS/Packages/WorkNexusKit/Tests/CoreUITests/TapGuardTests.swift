import XCTest
@testable import CoreUI

/// The first tap runs at once; repeats are dropped while it runs and for the cooldown after. Nothing is ever delayed.
@MainActor
final class TapGuardTests: XCTestCase {
    func testTheFirstTapRunsAtOnceAndRepeatsAreDroppedForTheCooldown() async throws {
        let tap = TapGuard(cooldown: 0.08)
        var ran = 0
        XCTAssertTrue(tap.run { ran += 1 })
        XCTAssertEqual(ran, 1, "run inside the call, not later")
        XCTAssertTrue(tap.isLocked)
        XCTAssertFalse(tap.run { ran += 1 })
        XCTAssertEqual(ran, 1)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(tap.isLocked)
        XCTAssertTrue(tap.run { ran += 1 })
        XCTAssertEqual(ran, 2)
    }

    func testNoCooldownUnlocksAsSoonAsTheActionIsOver() {
        let tap = TapGuard(cooldown: 0)
        var ran = 0
        tap.run { ran += 1 }
        XCTAssertFalse(tap.isLocked)
        tap.run { ran += 1 }
        XCTAssertEqual(ran, 2)
    }

    func testAnAsyncActionHoldsTheLockUntilItIsOver() async throws {
        let tap = TapGuard(cooldown: 0)
        var open = true, ran = 0
        XCTAssertTrue(tap.run { @MainActor in ran += 1; while open { try? await Task.sleep(for: .milliseconds(5)) } })
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(ran, 1)
        XCTAssertFalse(tap.run { ran += 1 }, "still open: a second tap is dropped")
        open = false
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertFalse(tap.isLocked)
        XCTAssertTrue(tap.run { ran += 1 })
        XCTAssertEqual(ran, 2)
    }

    func testAnActionThatNeverEndsLosesTheLockAfterTheTimeout() async throws {
        let tap = TapGuard(cooldown: 0, inFlightTimeout: 0.08)
        tap.run { @MainActor in try? await Task.sleep(for: .seconds(30)) }
        XCTAssertTrue(tap.isLocked)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(tap.isLocked, "a stuck request does not disable the button for good")
    }

    func testReleaseUnlocksAtOnceAndAnEarlierRunCannotUnlockALaterOne() async throws {
        let tap = TapGuard(cooldown: 0.05)
        tap.run {}
        tap.release()
        XCTAssertFalse(tap.isLocked)
        // A new run right away: the first run's cooldown timer must not unlock it.
        var open = true
        tap.run { @MainActor in while open { try? await Task.sleep(for: .milliseconds(5)) } }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(tap.isLocked)
        open = false
    }

    func testButtonsSharingAKeyCannotRunTogether() async throws {
        TapGuard.releaseAllShared()
        var ran: [String] = []
        XCTAssertTrue(TapGuard.runShared("open-detail", cooldown: 0.05) { ran.append("list") })
        XCTAssertFalse(TapGuard.runShared("open-detail", cooldown: 0.05) { ran.append("toolbar") })
        XCTAssertTrue(TapGuard.isSharedLocked("open-detail"))
        XCTAssertTrue(TapGuard.runShared("another", cooldown: 0.05) { ran.append("other") }, "another key is another guard")
        XCTAssertEqual(ran, ["list", "other"])
        TapGuard.releaseShared("open-detail")
        XCTAssertFalse(TapGuard.isSharedLocked("open-detail"))
        TapGuard.releaseAllShared()
    }
}
