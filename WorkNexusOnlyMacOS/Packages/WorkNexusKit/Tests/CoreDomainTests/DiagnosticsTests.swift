import Foundation
import XCTest
@testable import CoreDomain

/// The diagnostics log never keeps secrets, gives each error the steps before it, and records only failed requests.
final class DiagnosticsTests: XCTestCase {
    final class Collect: DiagnosticsSink, @unchecked Sendable {
        let lock = NSLock()
        var entries: [(DiagnosticEntry, [String])] = []
        func write(_ entry: DiagnosticEntry, trail: [String]) { lock.withLock { entries.append((entry, trail)) } }
        func flush() {}
    }

    enum ToolError: Error { case cancelled, offline }

    private var sink = Collect()
    override func setUp() { sink = Collect(); Diagnostics.install(sink, now: { Date(timeIntervalSince1970: 0) }) }
    override func tearDown() { Diagnostics.install(nil) }

    func testSecretsAndUrlQueriesNeverReachTheLog() {
        let r = Diagnostics.redact
        XCTAssertEqual(r("GET https://zt.example.com/index.php?m=bug&f=view&zentaosid=abc123 failed"), "GET https://zt.example.com/index.php?… failed")
        XCTAssertEqual(r("Authorization: Bearer eyJhbGciOi.payload.sig"), "Authorization: Bearer ***")
        XCTAssertEqual(r("login failed password=hunter2&account=jun"), "login failed password=***&account=jun")
        XCTAssertEqual(r(#"{"token":"s3cr3t","name":"x"}"#), #"{"token":"***","name":"x"}"#)
        XCTAssertEqual(r("PRIVATE-TOKEN: glpat-xyz"), "PRIVATE-TOKEN: ***")
        XCTAssertEqual(r("Cookie=zentaosid=1; lang=en"), "Cookie=***; lang=en")
        XCTAssertEqual(r("line one\nline two"), "line one ⏎ line two", "one entry stays one line")
        XCTAssertEqual(r(String(repeating: "a", count: 3000)).count, Diagnostics.messageLimit + 1)
    }

    func testARequestIsDescribedWithoutItsQueryButWithZenTaosPage() {
        let url = URL(string: "https://zt.example.com/zentao/index.php?m=bug&f=browse&productID=3&zentaosid=abc")!
        XCTAssertEqual(Diagnostics.describe(method: "GET", url: url), "GET zt.example.com/zentao/index.php?m=bug&f=browse")
        XCTAssertEqual(Diagnostics.describe(method: "POST", url: URL(string: "https://zt.example.com/api.php/v1/todos")!),
                       "POST zt.example.com/api.php/v1/todos")
    }

    func testOnlyFailedRequestsAreRecordedAndHowBadDependsOnTheAnswer() {
        let url = URL(string: "https://zt.example.com/api.php/v1/bugs/1")!
        Diagnostics.request("zentao", method: "GET", url: url, status: 200, elapsed: 0.1)
        Diagnostics.request("zentao", method: "GET", url: url, status: nil, error: CancellationError(), elapsed: 0.1)
        Diagnostics.request("zentao", method: "GET", url: url, status: nil, error: URLError(.cancelled), elapsed: 0.1)
        // A tool's own "cancelled" (an image load given up as the user moved on, logged as an error before).
        Diagnostics.request("zentao", method: "GET", url: url, status: nil, error: ToolError.cancelled, elapsed: 0)
        Diagnostics.request("zentao", method: "GET", url: url, status: nil, error: Failure.cancelled("cancelled"), elapsed: 0)
        XCTAssertTrue(sink.entries.isEmpty, "a success or a cancelled request is not a failure")
        Diagnostics.request("zentao", method: "GET", url: url, status: 404, elapsed: 0.25)
        Diagnostics.request("zentao", method: "GET", url: url, status: 401, elapsed: 0.1)
        Diagnostics.request("zentao", method: "GET", url: url, status: 502, elapsed: 0.1)
        Diagnostics.request("zentao", method: "GET", url: url, status: nil, error: URLError(.notConnectedToInternet), elapsed: 0.1)
        Diagnostics.request("zentao", method: "GET", url: url, status: nil, error: ToolError.offline, elapsed: 0.1)
        XCTAssertEqual(sink.entries.map(\.0.level), [.warning, .error, .error, .error, .error])
        XCTAssertEqual(sink.entries[0].0.message, "GET zt.example.com/api.php/v1/bugs/1 → HTTP 404 (250 ms)")
        XCTAssertEqual(sink.entries[0].0.area, "zentao")
    }

    func testAnErrorCarriesTheStepsBeforeItAndTheNextOneOnlyWhatCameAfter() {
        Diagnostics.step("chat"); Diagnostics.step("chat"); Diagnostics.step("account:zt1 / zentao.bugs #3")
        Diagnostics.info("app", "Started")
        Diagnostics.error("sync", "Account zt1: offline")
        Diagnostics.step("ticket zt1:bug:9")
        Diagnostics.error("ui", "Couldn't save")
        XCTAssertEqual(sink.entries[0].1, [], "only errors take the steps")
        XCTAssertEqual(sink.entries[1].1, ["chat", "account:zt1 / zentao.bugs #3"], "a repeated step is kept once")
        XCTAssertEqual(sink.entries[2].1, ["ticket zt1:bug:9"])
        for i in 0..<(Diagnostics.trailLength + 5) { Diagnostics.step("s\(i)") }
        Diagnostics.error("ui", "x")
        XCTAssertEqual(sink.entries.last?.1.count, Diagnostics.trailLength)
        XCTAssertEqual(sink.entries.last?.1.last, "s\(Diagnostics.trailLength + 4)")
    }

    func testNothingIsRecordedWithoutASink() {
        Diagnostics.install(nil)
        Diagnostics.error("ui", "lost")
        XCTAssertTrue(sink.entries.isEmpty)
    }
}
