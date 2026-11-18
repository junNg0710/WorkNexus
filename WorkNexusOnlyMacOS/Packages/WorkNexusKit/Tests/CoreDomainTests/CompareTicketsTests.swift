import XCTest
@testable import CoreDomain

/// Ported from: test/domain/compare_tickets_test.dart (the `boardComparator` group).
final class CompareTicketsTests: XCTestCase {
    private let day1 = Date(timeIntervalSince1970: 1_767_225_600)       // 2026-01-01
    private lazy var day2 = day1.addingTimeInterval(86_400)

    private func t(_ key: String, priority: Priority = .medium, title: String = "Title", updated: Date? = nil,
                   severity: Int? = nil, assignee: String? = nil, deadline: String? = nil) -> Ticket {
        Ticket(id: "t\(key)", accountId: "a", projectId: "p", providerType: .github, externalKey: key, title: title, body: "",
               priority: priority, status: .todo, providerStatus: "", sourceHash: "h", assignee: assignee, severity: severity,
               updatedAt: updated, providerEntity: deadline.map { .zentaoTask(ZenTaoTaskEntity(deadline: $0)) })
    }

    private func keys(_ tickets: [Ticket], _ sort: TicketSort) -> [String] {
        CompareTickets.boardOrdered(tickets, by: sort).map(\.externalKey)
    }

    func testDefaultIsMostUrgentFirstThenMostRecentlyUpdated() {
        let tickets = [t("1", priority: .low, updated: day2), t("2", priority: .urgent, updated: day1), t("3", priority: .urgent, updated: day2)]
        XCTAssertEqual(keys(tickets, .boardDefault), ["3", "2", "1"])
    }

    func testCreatedDescendingPutsTheNewestTicketFirst() {
        XCTAssertEqual(keys([t("9"), t("10"), t("2")], TicketSort(.id, descending: true)), ["10", "9", "2"])
    }

    func testUpdatedDescendingPutsTheMostRecentFirstMissingLast() {
        let tickets = [t("1", updated: day1), t("2"), t("3", updated: day2)]
        XCTAssertEqual(keys(tickets, TicketSort(.updated, descending: true)), ["3", "1", "2"])
    }

    func testTitleAscendingIgnoresCaseAndTiesFallBackToUpdated() {
        let tickets = [t("1", title: "beta"), t("2", title: "Alpha", updated: day1), t("3", title: "alpha", updated: day2)]
        XCTAssertEqual(keys(tickets, TicketSort(.title)), ["3", "2", "1"])
    }

    func testSeverityAscendingPutsUnsetSeverityFirst() {
        XCTAssertEqual(keys([t("1", severity: 3), t("2", severity: 1), t("3")], TicketSort(.severity)), ["3", "2", "1"])
    }

    func testAssigneeIgnoresCase() {
        XCTAssertEqual(keys([t("1", assignee: "cat"), t("2", assignee: "Bob"), t("3", assignee: "anna")], TicketSort(.assignee)),
                       ["3", "2", "1"])
    }

    /// macOS-only: a board sorted by deadline keeps cards without one last either way, and orders equals by priority.
    func testDeadlineKeepsCardsWithoutOneLastEitherWay() {
        let tickets = [t("far", deadline: "2026-02-09"), t("none", priority: .urgent), t("late", priority: .low, deadline: "2026-01-01"),
                       t("soonLow", priority: .low, deadline: "2026-01-05"), t("soonHigh", priority: .high, deadline: "2026-01-05")]
        XCTAssertEqual(keys(tickets, TicketSort(.deadline)), ["late", "soonHigh", "soonLow", "far", "none"])
        XCTAssertEqual(keys(tickets, TicketSort(.deadline, descending: true)), ["far", "soonHigh", "soonLow", "late", "none"])
    }

    /// The paged tables' order (`by`, no board tie-break): missing first ascending, newest id among equals.
    func testTableComparatorBreaksTiesByNewestId() {
        let compare = CompareTickets.by(TicketSort(.priority))
        let sorted = [t("1"), t("3", priority: .urgent), t("2")].sorted { compare($0, $1) < 0 }.map(\.externalKey)
        XCTAssertEqual(sorted, ["3", "2", "1"])
    }

    func testTheBoardsOfferEveryFieldButStatusAndSeverityOnlyWithBugs() {
        XCTAssertEqual(TicketSortField.boardFields, [.priority, .updated, .id, .title, .assignee])
        XCTAssertEqual(TicketSortField.boardFieldsWithSeverity, [.priority, .severity, .updated, .id, .title, .assignee])
        XCTAssertEqual(TicketSort.boardDefault, TicketSort(.priority))
    }
}
