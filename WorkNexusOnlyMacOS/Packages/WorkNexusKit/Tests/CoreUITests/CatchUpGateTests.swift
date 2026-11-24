import XCTest
@testable import CoreUI

@MainActor
final class CatchUpGateTests: XCTestCase {
    func testWithNothingWaitingAJobRunsAtOnce() {
        let gate = CatchUpGate { false }
        var ran: [Int] = []
        gate.run { ran.append(1) }
        gate.run { ran.append(2) }
        XCTAssertEqual(ran, [1, 2])
        XCTAssertFalse(gate.hasPending)
    }

    func testOnlyTheLastJobRunsOnceTheUserIsCaughtUpWith() async throws {
        var behind = true
        let gate = CatchUpGate(recheck: 0.01) { behind }
        var ran: [Int] = []
        gate.run { ran.append(1) }
        gate.run { ran.append(2) }
        gate.run { ran.append(3) }
        XCTAssertEqual(ran, [], "another click is waiting: nothing is built yet")
        XCTAssertTrue(gate.hasPending)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(ran, [], "still behind")
        behind = false
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(ran, [3])
        XCTAssertFalse(gate.hasPending)
    }

    /// The click that was waiting was not one of these (it handed in nothing): the kept job still runs.
    func testAKeptJobIsNotLostWhenNothingReplacesIt() async throws {
        var behind = true
        let gate = CatchUpGate(recheck: 0.01) { behind }
        var ran = 0
        gate.run { ran += 1 }
        behind = false
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(ran, 1)
    }

    func testACancelledJobNeverRuns() async throws {
        var behind = true
        let gate = CatchUpGate(recheck: 0.01) { behind }
        var ran = 0
        gate.run { ran += 1 }
        gate.cancel()
        behind = false
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(ran, 0)
        // And the gate still works afterwards.
        gate.run { ran += 1 }
        XCTAssertEqual(ran, 1)
    }

    /// `isBehind` being wrong must not swallow a click: the job runs once the gate has waited long enough.
    func testAJobIsNotKeptForever() async throws {
        let gate = CatchUpGate(recheck: 0.01, patience: 0.08) { true }
        var ran = 0
        gate.run { ran += 1 }
        XCTAssertEqual(ran, 0)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(ran, 1)
    }
}
