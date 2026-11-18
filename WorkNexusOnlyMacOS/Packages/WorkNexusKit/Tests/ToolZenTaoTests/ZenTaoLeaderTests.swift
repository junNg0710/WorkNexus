import CoreDomain
import SharedKit
import XCTest
@testable import ToolZenTao

final class ZenTaoLeaderTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }
    /// Wednesday 2026-11-18, midday (ZenTao's own week starts on Monday: Mon 16 ... Sun 22).
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12))! }

    private func day(_ offset: Int) -> String {
        let d = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private func task(_ id: String, assignee: String? = "an", status: String = "doing", deadline: Int? = nil, pri: Priority = .medium,
                      estimate: Double? = 4, left: Double? = 2, updatedDaysAgo: Int = 0, title: String = "Task") -> Ticket {
        Ticket(id: id, accountId: "a", projectId: "p", providerType: .zentao, externalKey: id, title: title, body: "", priority: pri,
               status: status == "done" || status == "closed" ? .done : (status == "wait" ? .todo : .inprogress), providerStatus: status, sourceHash: id,
               externalType: "Task", assignee: assignee,
               updatedAt: cal.date(byAdding: .day, value: -updatedDaysAgo, to: now),
               providerEntity: .zentaoTask(ZenTaoTaskEntity(estimate: estimate, left: left, deadline: deadline.map(day))))
    }

    private func bug(_ id: String, assignee: String? = "an", status: String = "active", deadline: Int? = nil) -> Ticket {
        Ticket(id: id, accountId: "a", projectId: "p", providerType: .zentao, externalKey: id, title: "Bug", body: "", priority: .medium,
               status: status == "closed" ? .done : .todo, providerStatus: status, sourceHash: id, externalType: "Bug", assignee: assignee,
               providerEntity: .zentaoBug(ZenTaoBugEntity(deadline: deadline.map(day))))
    }

    private func ids(_ f: ZenTaoLeaderFilter, _ tickets: [Ticket], names: [String: String] = [:]) -> [String] {
        ApplyLeaderFilter()(tickets, f, names: names, now: now, calendar: cal).map(\.id)
    }

    func testDeadlineStateCountsCalendarDaysAndIgnoresFinishedWork() {
        func state(_ t: Ticket) -> ZenTaoDeadlineState { zentaoDeadlineState(t, now: now, calendar: cal) }
        XCTAssertEqual(state(task("1", deadline: -2)), .overdue(days: 2))
        XCTAssertEqual(state(task("2", deadline: 0)), .today)          // due today is not late, however late in the day
        XCTAssertEqual(state(task("3", deadline: 2)), .upcoming(days: 2))
        XCTAssertEqual(state(task("4")), .none)
        XCTAssertEqual(state(task("5", status: "done", deadline: -9)), .finished)
        XCTAssertEqual(state(task("6", status: "cancel", deadline: -9)), .finished)
        XCTAssertEqual(state(bug("7", status: "closed", deadline: -9)), .finished)
        XCTAssertEqual(state(bug("8", status: "resolved", deadline: -1)), .overdue(days: 1))   // resolved still awaits its verification
    }

    func testEachQuickFilter() {
        let all = [
            task("late", deadline: -1), task("today", deadline: 0), task("soon", deadline: 3), task("far", deadline: 10),
            task("none"), task("done", status: "done", deadline: -5), task("free", assignee: nil),
            task("hot", pri: .urgent), task("high", pri: .high), task("old", updatedDaysAgo: 8), task("noest", estimate: nil),
        ]
        func run(_ chip: ZenTaoQuickFilter) -> [String] { ids(ZenTaoLeaderFilter(quick: [chip]), all) }
        XCTAssertEqual(run(.overdue), ["late"])
        XCTAssertEqual(run(.dueSoon), ["today", "soon"])
        XCTAssertEqual(run(.noDeadline), ["none", "free", "hot", "high", "old", "noest"])
        XCTAssertEqual(run(.unassigned), ["free"])
        XCTAssertEqual(run(.highPriority), ["hot", "high"])
        XCTAssertEqual(run(.stale), ["old"])
        XCTAssertEqual(run(.noEstimate), ["noest"])
        // The week is Monday 16 - Sunday 22: `today` (Wed), `soon` (Sat) are in it, yesterday's `late` is too (Tue) - it is still open.
        XCTAssertEqual(run(.dueThisWeek), ["late", "today", "soon"])
    }

    func testTimeChipsAreAlternativesAndOthersNarrow() {
        let all = [task("late", deadline: -1), task("soon", deadline: 1), task("lateFree", assignee: nil, deadline: -1), task("far", deadline: 20)]
        XCTAssertEqual(ids(ZenTaoLeaderFilter(quick: [.overdue, .dueSoon]), all), ["late", "soon", "lateFree"])
        XCTAssertEqual(ids(ZenTaoLeaderFilter(quick: [.overdue, .unassigned]), all), ["lateFree"])
    }

    func testPeopleAndKeywordCombine() {
        let all = [task("1", assignee: "an", title: "Login page"), task("2", assignee: "binh", title: "Login API"),
                   task("3", assignee: "an", title: "Settings"), task("4", assignee: nil, title: "Login bug")]
        XCTAssertEqual(ids(ZenTaoLeaderFilter(people: ["an"]), all), ["1", "3"])
        XCTAssertEqual(ids(ZenTaoLeaderFilter(people: ["an", "binh"], keyword: "login"), all), ["1", "2"])
        XCTAssertEqual(ids(ZenTaoLeaderFilter(keyword: "#3"), all), ["3"])
        // A keyword also finds the work by the name its holder goes by.
        XCTAssertEqual(ids(ZenTaoLeaderFilter(keyword: "Binh Tran"), all, names: ["binh": "Binh Tran"]), ["2"])
        XCTAssertEqual(ids(ZenTaoLeaderFilter(), all), ["1", "2", "3", "4"])
    }

    func testCountsAreWhatEachChipWouldKeep() {
        let all = [task("a", deadline: -1), task("b", deadline: -3), task("c", assignee: nil), task("d", status: "done", deadline: -1)]
        let counts = CountQuickFilters()(all, now: now, calendar: cal)
        XCTAssertEqual(counts[.overdue], 2)
        XCTAssertEqual(counts[.unassigned], 1)
        XCTAssertEqual(counts[.noDeadline], 1)
    }

    func testWorkloadPerPersonBusiestFirstUnassignedLast() {
        let all = [
            task("1", assignee: "an", deadline: -1, left: 3), task("2", assignee: "an", deadline: 1, pri: .urgent, left: 5),
            task("3", assignee: "binh", left: 1), task("4", assignee: "binh", left: 1), task("5", assignee: "binh", left: 1),
            task("6", assignee: nil), task("7", assignee: "an", status: "done", deadline: -4), bug("8", assignee: "an"),
        ]
        let rows = SummarizeWorkload()(all, roster: ["an", "binh", "chi"], now: now, calendar: cal)
        XCTAssertEqual(rows.map(\.login), ["an", "binh", "chi", ""])
        let an = rows[0]
        XCTAssertEqual(an.open, 3)                 // the done task is not load; the bug is
        XCTAssertEqual(an.overdue, 1)
        XCTAssertEqual(an.dueSoon, 1)
        XCTAssertEqual(an.highPriority, 1)
        XCTAssertEqual(an.hoursLeft, 8)
        XCTAssertEqual(rows[1].open, 3)
        XCTAssertEqual(rows[2].open, 0)            // on the roster, holding nothing
        XCTAssertTrue(rows[3].isUnassigned)
        XCTAssertEqual(rows[3].open, 1)
    }

    func testFilterToggles() {
        var f = ZenTaoLeaderFilter()
        XCTAssertFalse(f.isActive)
        f = f.toggled(.overdue).toggled(person: "an")
        XCTAssertTrue(f.isActive)
        XCTAssertEqual(f.toggled(.overdue).quick, [])
        XCTAssertEqual(f.toggled(person: "an").people, [])
        XCTAssertFalse(f.clearedAll().isActive)
        XCTAssertTrue(ZenTaoLeaderFilter(keyword: "  x ").isActive)
        XCTAssertFalse(ZenTaoLeaderFilter(keyword: "   ").isActive)
    }

    // MARK: On the board

    private func query(_ tickets: [Ticket], sort: TicketSort = .boardDefault) -> BoardQuery {
        BoardQuery(tickets: tickets, filter: FilterState(), accountWorkspace: [:], now: now, sort: sort)
    }

    func testTaskBoardAppliesTheLeaderFilterToItsColumns() {
        let tickets = [task("1", assignee: "an", status: "doing", deadline: -2), task("2", assignee: "binh", status: "doing"),
                       task("3", assignee: "an", status: "wait", deadline: 5)]
        let board = BuildZenTaoTaskBoard(leader: ZenTaoLeaderFilter(people: ["an"]))(query(tickets))
        XCTAssertEqual(board.column(.inProgress)?.tickets.map(\.id), ["1"])
        XCTAssertEqual(board.column(.notStarted)?.tickets.map(\.id), ["3"])
        XCTAssertEqual(board.total, 2)
        let late = BuildZenTaoTaskBoard(leader: ZenTaoLeaderFilter(quick: [.overdue]))(query(tickets))
        XCTAssertEqual(late.total, 1)
    }

    func testColumnsCanBeOrderedByDeadline() {
        let tickets = [task("far", deadline: 9, pri: .urgent), task("none", pri: .urgent), task("late", deadline: -3, pri: .low), task("soon", deadline: 1)]
        let byDeadline = BuildZenTaoTaskBoard()(query(tickets, sort: TicketSort(.deadline)))
        XCTAssertEqual(byDeadline.column(.inProgress)?.tickets.map(\.id), ["late", "soon", "far", "none"])
        // Latest first, and still no deadline last.
        let latest = BuildZenTaoTaskBoard()(query(tickets, sort: TicketSort(.deadline, descending: true)))
        XCTAssertEqual(latest.column(.inProgress)?.tickets.map(\.id), ["far", "soon", "late", "none"])
        let byPriority = BuildZenTaoTaskBoard()(query(tickets))
        XCTAssertEqual(byPriority.column(.inProgress)?.tickets.map(\.id).prefix(2).sorted(), ["far", "none"])
    }

    func testDeadlineIsASortableColumn() {
        XCTAssertEqual(zentaoOrderBy(TicketSort(.deadline), bug: false), "deadline_asc")
        XCTAssertEqual(zentaoOrderBy(TicketSort(.deadline, descending: true), bug: true), "deadline_desc")
    }
}
