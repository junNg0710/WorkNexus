/// Ported from: lib/features/chat/presentation/providers/merge_request_providers.dart (`_kFresh`, resume refetch)
import CoreDomain
import XCTest
@testable import FeatureChat

final class MergeRequestFreshnessTests: XCTestCase {
    private func ticket(_ status: String) -> Ticket {
        Ticket(id: "t", accountId: "a", projectId: "p", providerType: .gitlab, externalKey: "1", title: "MR", body: "", priority: .medium,
               status: .todo, providerStatus: status, sourceHash: "")
    }

    func testAMissingOrNeverFetchedItemIsFetched() {
        let f = MergeRequestFreshness()
        XCTAssertTrue(f.needsFetch("u", stored: nil, resumed: false))
        XCTAssertTrue(f.needsFetch("u", stored: ticket("opened"), resumed: false))
    }

    func testAFreshFetchIsTrustedForFiveMinutes() {
        var f = MergeRequestFreshness()
        let t0 = Date(timeIntervalSince1970: 1000)
        f.fetched("u", at: t0)
        XCTAssertFalse(f.needsFetch("u", stored: ticket("opened"), resumed: false, now: t0.addingTimeInterval(299)))
        XCTAssertTrue(f.needsFetch("u", stored: ticket("opened"), resumed: false, now: t0.addingTimeInterval(301)))
        // Coming back to the app refetches one still open, however fresh.
        XCTAssertTrue(f.needsFetch("u", stored: ticket("opened"), resumed: true, now: t0.addingTimeInterval(1)))
    }

    func testMergedAndClosedAreFinal() {
        let f = MergeRequestFreshness()
        for status in ["merged", "Closed"] {
            XCTAssertFalse(f.needsFetch("u", stored: ticket(status), resumed: true))
            XCTAssertFalse(f.needsFetch("u", stored: ticket(status), resumed: false))
        }
    }
}
