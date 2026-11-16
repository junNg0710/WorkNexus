import CoreDomain
import XCTest
@testable import FeatureWorkspaceOverview

final class OverviewPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testShortWhenBuckets() {
        XCTAssertEqual(shortWhen(nil, now: now), "")
        XCTAssertEqual(shortWhen(now.addingTimeInterval(-30), now: now), "just now")
        XCTAssertEqual(shortWhen(now.addingTimeInterval(-5 * 60), now: now), "5m ago")
        XCTAssertEqual(shortWhen(now.addingTimeInterval(-3 * 3600), now: now), "3h ago")
        XCTAssertEqual(shortWhen(now.addingTimeInterval(-4 * 86400), now: now), "4d ago")
        XCTAssertEqual(shortWhen(now.addingTimeInterval(-10 * 86400), now: now, locale: Locale(identifier: "en_US")),
                       monthDay(now.addingTimeInterval(-10 * 86400), locale: Locale(identifier: "en_US")))
    }

    func testZenTaoDatesDropTheEmptyForms() {
        XCTAssertNil(parseZenTaoDate(nil)); XCTAssertNil(parseZenTaoDate("")); XCTAssertNil(parseZenTaoDate("0000-00-00"))
        let d = parseZenTaoDate("2026-10-12")!
        XCTAssertEqual(Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: d).day, 12)
    }

    func testStatusWordsFollowZenTaosOwn() {
        XCTAssertEqual(myWorkStatusLabel(.inbox, bug: true), "Unconfirmed")
        XCTAssertEqual(myWorkStatusLabel(.todo, bug: true), "To fix")
        XCTAssertEqual(myWorkStatusLabel(.review, bug: true), "Resolved")
        XCTAssertEqual(myWorkStatusLabel(.blocked, bug: false), "Paused")
        XCTAssertEqual(myWorkStatusLabel(.todo, bug: false), "Not started")
        XCTAssertEqual(zentaoStatusWord("suspended", execution: true), "Paused")
        XCTAssertEqual(zentaoStatusWord("done", execution: false), "Done")
        XCTAssertEqual(zentaoStatusWord("odd", execution: false), "odd")
    }

    func testPluralsNeverShowRawICU() {
        XCTAssertEqual(OL.dashboardDaysLeft(0), "ends today"); XCTAssertEqual(OL.dashboardDaysLeft(1), "1 day left")
        XCTAssertEqual(OL.dashboardDaysLeft(11), "11 days left"); XCTAssertEqual(OL.dashboardDaysOverdue(2), "2 days overdue")
        XCTAssertEqual(OL.subtasks(1), "1 subtask"); XCTAssertEqual(OL.subtasks(3), "3 subtasks")
        XCTAssertFalse(OL.showAllWithCount(7).contains("%"))
    }
}
