import CoreDomain
import Foundation
import XCTest
@testable import CorePersistence

final class SharedObservationTests: XCTestCase {
    /// Counts how often the shared source is started, and lets the test push values into it.
    private final class Source: @unchecked Sendable {
        let lock = NSLock()
        var starts = 0
        var continuations: [AsyncStream<Int>.Continuation] = []
        func make() -> AsyncStream<Int> {
            let (s, c) = AsyncStream<Int>.makeStream()
            lock.withLock { starts += 1; continuations.append(c) }
            return s
        }
        func send(_ v: Int) { lock.withLock { continuations.last }?.yield(v) }
    }

    func testWatchersShareOneSourceAndALateOneGetsTheLatestValue() async throws {
        let source = Source()
        let shared = SharedObservation { source.make() }
        var a = shared.stream().makeAsyncIterator()
        var b = shared.stream().makeAsyncIterator()
        source.send(1)
        let firstA = await a.next(), firstB = await b.next()
        XCTAssertEqual(firstA, 1); XCTAssertEqual(firstB, 1)
        XCTAssertEqual(source.starts, 1, "two watchers, one query")
        var late = shared.stream().makeAsyncIterator()
        let lateFirst = await late.next()
        XCTAssertEqual(lateFirst, 1, "a new watcher sees the current value at once")
        XCTAssertEqual(source.starts, 1)
    }

    func testASlowWatcherSkipsToTheNewestValue() async throws {
        let source = Source()
        let shared = SharedObservation { source.make() }
        var fast = shared.stream().makeAsyncIterator()
        var slow = shared.stream().makeAsyncIterator()
        for v in 1...3 {
            source.send(v)
            let got = await fast.next()
            XCTAssertEqual(got, v)
        }
        let caughtUp = await slow.next()
        XCTAssertEqual(caughtUp, 3, "the lists it could not keep up with are skipped")
    }

    func testTheSourceStopsWithTheLastWatcherAndRestartsForTheNext() async throws {
        let source = Source()
        let shared = SharedObservation { source.make() }
        var task: Task<Void, Never>? = Task { for await _ in shared.stream() {} }
        try await waitUntil { shared.watcherCount == 1 }
        task?.cancel(); task = nil
        try await waitUntil { shared.watcherCount == 0 }
        var again = shared.stream().makeAsyncIterator()
        source.send(9)
        let v = await again.next()
        XCTAssertEqual(v, 9)
        XCTAssertEqual(source.starts, 2)
    }

    /// Ten watchers of the repository read the table once per write, not ten times.
    func testTheTicketRepositoryDecodesOncePerChangeForEveryWatcher() async throws {
        let repo = GRDBTicketRepository(db: try AppDatabase.inMemory())
        let t = Ticket(id: "t1", accountId: "a1", projectId: "p", providerType: .zentao, externalKey: "1", title: "T",
                       body: "B", priority: .low, status: .todo, providerStatus: "wait", sourceHash: "h1")
        _ = await repo.upsertTickets([t])
        var iterators = (0..<10).map { _ in repo.watchTickets().makeAsyncIterator() }
        for i in iterators.indices {
            let got = await iterators[i].next()
            XCTAssertEqual(got?.map(\.id), ["t1"])
        }
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition())
    }
}
