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

    /// A late frame says what the main thread was busy with, and how much of the delay nothing measured explains.
    func testLateFramesNameTheWorkThatHeldThemUp() {
        var spans = WorkSpans()
        spans.add("board: build zentao tasks", start: 10.0, end: 10.4)
        spans.add("tiny", start: 10.4, end: 10.401)
        spans.add("db: read every ticket", start: 9.0, end: 10.1)
        let busy = spans.busy(from: 10.0, to: 10.6)
        XCTAssertEqual(busy["board: build zentao tasks"] ?? 0, 0.4, accuracy: 1e-9)
        XCTAssertEqual(busy["db: read every ticket"] ?? 0, 0.1, accuracy: 1e-9, "only the part inside the window")
        XCTAssertNil(busy["tiny"], "too short to keep")
        XCTAssertEqual(WorkSpans.describe(busy, late: 0.6), "busy with board: build zentao tasks 400 ms, db: read every ticket 100 ms, 100 ms unmeasured")

        var w = FrameStutterWindow()
        let frame = 1.0 / 60
        XCTAssertEqual(w.add(gap: 1.5 + frame, frame: frame, now: 1, busy: ["board: scope zentao tasks": 1.2]),
                       "Not responding for 1500 ms, busy with board: scope zentao tasks 1200 ms, 300 ms unmeasured")
        _ = w.add(gap: 0.1 + frame, frame: frame, now: 2, busy: ["board: build zentao bugs": 0.1])
        _ = w.add(gap: 0.2 + frame, frame: frame, now: 3, busy: ["board: build zentao bugs": 0.2])
        XCTAssertEqual(w.close(), "Stutter: 2 late frames in 5 s, worst 200 ms, 300 ms lost, busy with board: build zentao bugs 300 ms")
    }

    func testMainThreadWorkIsKeptWhileOnAndASlowClickIsWrittenWhenShown() {
        PerformanceLog.setEnabled(true); sink.entries = []
        Diagnostics.step("account:a / zentao.tasks")
        let start = PerformanceLog.now()
        PerformanceLog.beginInteraction("open zentao.bugs")
        PerformanceLog.beginInteraction("open scope 7")   // set off by the first: the click's name is kept
        _ = PerformanceLog.measureSync("board: build zentao bugs", slowerThan: 10, detail: "40 tickets") { Thread.sleep(forTimeInterval: 0.12) }
        XCTAssertGreaterThan(PerformanceLog.busy(from: start, to: PerformanceLog.now())["board: build zentao bugs"] ?? 0, 0.1)
        PerformanceLog.frameShown(at: PerformanceLog.now())
        let lines = sink.entries.map(\.0.message)
        XCTAssertEqual(lines.count, 1, "\(lines)")
        XCTAssertTrue(lines[0].hasPrefix("Slow: open zentao.bugs took "), lines[0])
        XCTAssertTrue(lines[0].contains("ms to show, busy with board: build zentao bugs "), lines[0])
        PerformanceLog.frameShown(at: PerformanceLog.now())
        XCTAssertEqual(sink.entries.count, 1, "an action is answered once")
        PerformanceLog.setEnabled(false)
        PerformanceLog.beginInteraction("off")
        XCTAssertTrue(PerformanceLog.busy(from: 0, to: .greatestFiniteMagnitude).isEmpty, "nothing is kept while off")
    }
}
