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
