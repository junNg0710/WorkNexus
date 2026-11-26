// Not in the Flutter app: the log says how the last session ended, from the report macOS wrote.
import XCTest
@testable import CoreUI

final class CrashReportsTests: XCTestCase {
    /// A report shaped as macOS writes one (`.ips`): a line of JSON, then the JSON body.
    private func report(process: String = "WorkNexusMac", message: String? = "Fatal error: Index out of range", frames: Int = 3) -> String {
        var deep: [String] = (0..<frames).map { #"{"imageOffset":\#(4096 + $0),"symbol":"systemFrame\#($0)","symbolLocation":\#($0 * 4),"imageIndex":1}"# }
        deep.append(#"{"imageOffset":70000,"imageIndex":0}"#)
        deep.append(#"{"imageOffset":1064,"symbol":"closure #1 in ChatShellModel.select(_:)","symbolLocation":124,"imageIndex":0}"#)
        let asi = message.map { #""asi":{"libswiftCore.dylib":["\#($0)"]},"# } ?? ""
        return #"{"app_name":"\#(process)","timestamp":"2026-11-26 17:30:04.00 +0700","app_version":"1.9.37","build_version":"58","bug_type":"309","name":"\#(process)"}"#
            + "\n" + #"""
            {"procName":"\#(process)","captureTime":"2026-11-26 17:30:03.9009 +0700",
             "bundleInfo":{"CFBundleShortVersionString":"1.9.37","CFBundleVersion":"58"},
             "exception":{"codes":"0x0000000000000001, 0x0000000104560428","type":"EXC_BREAKPOINT","signal":"SIGTRAP"},
             "termination":{"flags":0,"code":5,"namespace":"SIGNAL","indicator":"Trace/BPT trap: 5","byProc":"exc handler","byPid":2839},
             \#(asi)"faultingThread":1,
             "threads":[{"id":1,"frames":[{"imageOffset":8,"symbol":"mach_msg2_trap","symbolLocation":8,"imageIndex":1}]},
                        {"triggered":true,"id":2,"queue":"com.apple.main-thread","frames":[\#(deep.joined(separator: ","))]}],
             "usedImages":[{"name":"\#(process)","base":4367712256},{"name":"libswiftCore.dylib","base":6634254336}]}
            """#
    }

    func testAReportBecomesTheLinesTheLogKeeps() throws {
        let summary = try XCTUnwrap(CrashReportSummary.parse(report()))
        XCTAssertEqual(summary.app, "WorkNexusMac 1.9.37 (58)")
        XCTAssertEqual(summary.time, "2026-11-26 17:30:03.9009 +0700")
        XCTAssertEqual(summary.exception, "EXC_BREAKPOINT (SIGTRAP), codes 0x0000000000000001, 0x0000000104560428")
        XCTAssertEqual(summary.termination, "SIGNAL 5 Trace/BPT trap: 5 by exc handler")
        XCTAssertEqual(summary.messages, ["Fatal error: Index out of range"])
        XCTAssertEqual(summary.thread, "thread 1 (com.apple.main-thread)")
        XCTAssertEqual(summary.frames, ["libswiftCore.dylib  systemFrame0 + 0", "libswiftCore.dylib  systemFrame1 + 4", "libswiftCore.dylib  systemFrame2 + 8",
                                        "WorkNexusMac + 0x11170", "WorkNexusMac  closure #1 in ChatShellModel.select(_:) + 124"])
        XCTAssertEqual(summary.lines.first, "WorkNexusMac 1.9.37 (58) crashed at 2026-11-26 17:30:03.9009 +0700: EXC_BREAKPOINT (SIGTRAP), "
                       + "codes 0x0000000000000001, 0x0000000104560428 — SIGNAL 5 Trace/BPT trap: 5 by exc handler")
        XCTAssertEqual(summary.lines[1], "  said: Fatal error: Index out of range")
        XCTAssertEqual(summary.lines[2], "  crashed thread 1 (com.apple.main-thread):")
    }

    func testTheAppsOwnFramesBelowALongSystemStackAreKept() throws {
        let summary = try XCTUnwrap(CrashReportSummary.parse(report(message: nil, frames: 14)))
        XCTAssertEqual(summary.frames.count, CrashReportSummary.topFrames + 2)
        XCTAssertEqual(summary.frames.suffix(2), ["… WorkNexusMac + 0x11170", "… WorkNexusMac  closure #1 in ChatShellModel.select(_:) + 124"])
        XCTAssertTrue(summary.messages.isEmpty)
    }

    func testWhatIsNotAReportIsNotRead() {
        XCTAssertNil(CrashReportSummary.parse("Process: WorkNexusMac [123]\nPath: /Applications/WorkNexusMac.app"))
        XCTAssertNil(CrashReportSummary.parse(""))
        XCTAssertNil(CrashReportSummary.parse("{\"app_name\":\"x\"}\nnot json"))
    }

    private func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("crash-reports-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func write(_ text: String, _ name: String, in dir: URL, at date: Date) throws {
        let url = dir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    func testOnlyThisAppsReportsSinceTheSessionStartedAreFoundNewestFirst() throws {
        let dir = try folder(), retired = dir.appendingPathComponent("Retired", isDirectory: true)
        try FileManager.default.createDirectory(at: retired, withIntermediateDirectories: true)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try write(report(), "WorkNexusMac-old.ips", in: dir, at: start.addingTimeInterval(-3600))
        try write(report(), "WorkNexusMac-a.ips", in: dir, at: start.addingTimeInterval(600))
        try write(report(), "WorkNexusMac-b.ips", in: retired, at: start.addingTimeInterval(900))
        try write(report(process: "Safari"), "Safari-c.ips", in: dir, at: start.addingTimeInterval(900))
        try write("{}", "WorkNexusMac-notes.json", in: dir, at: start.addingTimeInterval(900))
        let found = CrashReports.find(process: "WorkNexusMac", since: start, in: [dir, retired])
        XCTAssertEqual(found.map(\.lastPathComponent), ["WorkNexusMac-b.ips", "WorkNexusMac-a.ips"])
    }

    func testTheEndOfASessionIsTheCrashFoundOrThatNoneWas() throws {
        let dir = try folder(), start = Date(timeIntervalSince1970: 1_800_000_000)
        let none = CrashReports.describeEnd(process: "WorkNexusMac", since: start, in: [dir])
        XCTAssertEqual(none.count, 1)
        XCTAssertTrue(none[0].contains("no crash report"))
        try write(report(), "WorkNexusMac-2026-11-26-173004.ips", in: dir, at: start.addingTimeInterval(60))
        try write("plain text", "WorkNexusMac-2026-11-26-173005.crash", in: dir, at: start.addingTimeInterval(30))
        try write("hang", "WorkNexusMac_2026-11-26-172900_Mac.hang", in: dir, at: start.addingTimeInterval(10))
        let lines = CrashReports.describeEnd(process: "WorkNexusMac", since: start, in: [dir])
        XCTAssertTrue(lines[0].hasPrefix("WorkNexusMac 1.9.37 (58) crashed at"))
        XCTAssertTrue(lines.contains("  full report: WorkNexusMac-2026-11-26-173004.ips"))
        XCTAssertTrue(lines.contains("A crash report that could not be read: WorkNexusMac-2026-11-26-173005.crash"))
        XCTAssertEqual(lines.last, "macOS also noted the app not responding or overusing the Mac: WorkNexusMac_2026-11-26-172900_Mac.hang")
    }

    func testMemoryIsNotedNowAndThenAndAtOnceWhenItGrowsALot() {
        var policy = MemoryLogPolicy(every: 1800, growth: 200 << 20)
        let t = Date(timeIntervalSince1970: 1_800_000_000), mb: UInt64 = 1 << 20
        XCTAssertEqual(policy.line(bytes: 300 * mb, now: t), "Memory in use: 300 MB")
        XCTAssertNil(policy.line(bytes: 350 * mb, now: t.addingTimeInterval(60)), "neither time nor growth")
        XCTAssertEqual(policy.line(bytes: 520 * mb, now: t.addingTimeInterval(120)), "Memory in use: 520 MB (+220 MB since the last note)")
        XCTAssertNil(policy.line(bytes: 400 * mb, now: t.addingTimeInterval(180)), "shrinking is not news")
        XCTAssertEqual(policy.line(bytes: 400 * mb, now: t.addingTimeInterval(120 + 1800)), "Memory in use: 400 MB (-120 MB since the last note)")
    }

    func testTheProcessKnowsItsOwnMemory() {
        XCTAssertGreaterThan(ProcessMemory.footprint() ?? 0, 1 << 20)
    }
}

final class SessionMarkerTests: XCTestCase {
    private func marker() throws -> SessionMarker {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("marker-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return SessionMarker(url: dir.appendingPathComponent("Logs/.running"))
    }

    func testASessionThatQuitLeavesNothingBehind() throws {
        let m = try marker()
        XCTAssertNil(m.previous())
        m.begin()
        XCTAssertNotNil(m.previous())
        m.end()
        XCTAssertNil(m.previous())
    }

    func testASessionThatNeverQuitSaysWhenItStartedAndWasLastAlive() throws {
        let m = try marker()
        m.begin()
        let started = try XCTUnwrap(m.previous()).started
        m.touch(now: started.addingTimeInterval(3 * 3600))
        let left = try XCTUnwrap(m.previous())
        XCTAssertEqual(left.started.timeIntervalSince1970, started.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(left.lastSeen.timeIntervalSince(left.started), 3 * 3600, accuracy: 2)
        // The next launch starts its own count.
        m.begin()
        let fresh = try XCTUnwrap(m.previous())
        XCTAssertLessThan(fresh.lastSeen.timeIntervalSince(fresh.started), 2)
    }

    func testTheLineNamesTheLastTimeItWasAliveOnlyWhenTheMarkerWasTouched() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let touched = SessionMarker.describe(started: t, lastSeen: t.addingTimeInterval(7200))
        XCTAssertTrue(touched.contains("It started at ") && touched.contains(" and was last alive at "))
        XCTAssertFalse(SessionMarker.describe(started: t, lastSeen: t).contains("last alive"), "a marker of a version without the heartbeat")
    }
}
