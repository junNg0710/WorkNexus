import CoreDomain
import XCTest
@testable import CoreUI

@MainActor
final class MainThreadSamplerTests: XCTestCase {
    /// A main thread that stops answering is seen in the function that keeps it: the innermost one of this binary.
    func testSeesWhatTheMainThreadRunsWhileItIsSilent() {
        let sampler = MainThreadSampler()
        sampler.start()
        defer { sampler.stop() }
        XCTAssertTrue(sampler.beat().isEmpty, "nothing is looked at while frames come on time")
        XCTAssertGreaterThan(spinForTheSamplerTest(seconds: 0.4), 0)
        let stacks = sampler.beat(), again = sampler.beat()
        XCTAssertGreaterThan(stacks.count, 10, "looked at every 10 ms once silent for 30 ms")
        let seen = MainThreadSampler.tally(stacks)
        let here = seen.filter { $0.key.contains("spinForTheSamplerTest") }.values.reduce(0, +)
        XCTAssertGreaterThan(here, stacks.count / 2, "\(seen)")
        XCTAssertTrue(again.isEmpty, "what was seen is handed over once")
    }

    /// With none of the app's code on the stack, the place is the system function with what called it - and a thread only
    /// waiting for its next event is told apart from one held up.
    func testASystemPlaceSaysWhatItWasCalledForAndWaitingIsToldApart() {
        typealias S = MainThreadSampler.Symbol
        let trap = S(name: "mach_msg2_trap", image: "libsystem_kernel.dylib", isApp: false)
        let wrap = S(name: "mach_msg", image: "libsystem_kernel.dylib", isApp: false)
        let waiting = MainThreadSampler.systemPlace(trap, callers: [wrap, S(name: "__CFRunLoopServiceMachPort", image: "CoreFoundation", isApp: false)])
        XCTAssertEqual(waiting, StallSamples.idle)
        let committing = MainThreadSampler.systemPlace(trap, callers: [wrap, S(name: "CA::Context::commit_transaction", image: "QuartzCore", isApp: false)])
        XCTAssertEqual(committing, "mach_msg2_trap ← CA::Context::commit_transaction (QuartzCore)")
        XCTAssertEqual(MainThreadSampler.systemPlace(trap, callers: [wrap]), "mach_msg2_trap (libsystem_kernel.dylib)")
        XCTAssertTrue(StallSamples.onlyIdle([StallSamples.idle: 4]))
        XCTAssertFalse(StallSamples.onlyIdle([StallSamples.idle: 4, "X.load": 1]))
        XCTAssertFalse(StallSamples.onlyIdle([:]))
    }

    /// The names are found off the main thread and handed back on it.
    func testNamesCanBeFoundOffTheMainThread() async {
        let sampler = MainThreadSampler()
        sampler.start()
        defer { sampler.stop() }
        _ = spinForTheSamplerTest(seconds: 0.2)
        let stacks = sampler.beat()
        let seen = await withCheckedContinuation { (c: CheckedContinuation<[String: Int], Never>) in
            MainThreadSampler.tallyLater(stacks) { found in
                XCTAssertTrue(Thread.isMainThread)
                c.resume(returning: found)
            }
        }
        XCTAssertEqual(seen.values.reduce(0, +), stacks.count)
        XCTAssertTrue(seen.keys.contains { $0.contains("spinForTheSamplerTest") }, "\(seen)")
    }

    func testStoppedItLooksAtNothing() {
        let sampler = MainThreadSampler()
        sampler.start()
        sampler.stop()
        _ = spinForTheSamplerTest(seconds: 0.15)
        XCTAssertTrue(sampler.beat().isEmpty)
    }

    func testLooksStopAfterALongSilence() {
        XCTAssertLessThanOrEqual(Double(MainThreadSampler.mostPerSilence) * Double(MainThreadSampler.every) / 1_000_000, 2,
                                 "a screen asleep is not looked at for ever")
    }
}

/// Keeps the thread busy without a system call the whole time (the sampler names the innermost function of this binary).
@inline(never)
private func spinForTheSamplerTest(seconds: TimeInterval) -> Double {
    let end = ProcessInfo.processInfo.systemUptime + seconds
    var x = 1.0001
    while ProcessInfo.processInfo.systemUptime < end { for i in 1...2000 { x = (x * 1.000001 + Double(i)).truncatingRemainder(dividingBy: 97) } }
    return x
}
