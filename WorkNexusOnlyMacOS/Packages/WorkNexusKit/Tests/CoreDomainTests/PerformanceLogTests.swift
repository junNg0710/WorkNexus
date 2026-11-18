import Foundation
import XCTest
@testable import CoreDomain

/// The performance log: nothing while off; slow work and stutters, with where they happened, while on.
final class PerformanceLogTests: XCTestCase {
    private var sink = DiagnosticsTests.Collect()
    override func setUp() { sink = DiagnosticsTests.Collect(); Diagnostics.install(sink); PerformanceLog.setContext("chat", nil) }
    override func tearDown() { PerformanceLog.setEnabled(false); PerformanceLog.setContext("chat", nil); Diagnostics.install(nil) }

    func testNothingIsMeasuredOrWrittenWhileOff() async {
        PerformanceLog.setEnabled(false); sink.entries = []
        let v = await PerformanceLog.measure("slow", slowerThan: 0) { 7 }
        PerformanceLog.note("stutter")
        XCTAssertEqual(v, 7)
        XCTAssertTrue(sink.entries.isEmpty)
    }

    func testSlowWorkIsWrittenWithWhereItHappened() async {
        PerformanceLog.setEnabled(true); sink.entries = []
        Diagnostics.step("chat")
        PerformanceLog.setContext("chat", "20 chat rows on screen (3 pictures)")
        _ = await PerformanceLog.measure("chat: load older messages", slowerThan: 0) { () }
        _ = PerformanceLog.measureSync("fast", slowerThan: 10) { () }
        XCTAssertEqual(sink.entries.count, 1)
        let e = sink.entries[0].0
        XCTAssertEqual(e.area, "perf")
        XCTAssertTrue(e.message.hasPrefix("Slow: chat: load older messages took "), e.message)
        XCTAssertTrue(e.message.hasSuffix("— chat · 20 chat rows on screen (3 pictures)"), e.message)
    }

    func testLateFramesAreGatheredIntoOneLinePerWindow() {
        var w = FrameStutterWindow()
        let frame = 1.0 / 60
        XCTAssertNil(w.add(gap: frame, frame: frame, now: 0.0), "on time")
        XCTAssertNil(w.add(gap: frame + 0.03, frame: frame, now: 0.1), "a little late is not a stutter")
        XCTAssertNil(w.add(gap: frame + 0.08, frame: frame, now: 1))
        XCTAssertNil(w.add(gap: frame + 0.12, frame: frame, now: 2))
        let line = w.add(gap: frame, frame: frame, now: 6.1)
        XCTAssertEqual(line, "Stutter: 2 late frames in 5 s, worst 120 ms, 200 ms lost")
        XCTAssertNil(w.close(), "a window is written once")
        XCTAssertEqual(w.add(gap: 2.5, frame: frame, now: 10), "Not responding for 2483 ms")
    }
}
