/// Ported from: test/features/chat/presentation/message_list_item_test.dart (chatListItems, _sameRun)
import XCTest
@testable import FeatureChat

final class ChatListRowsTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func at(_ day: Int, _ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 3, day: day, hour: h, minute: m))! }
    private func chatMsg(_ gid: String, _ sender: Int, _ d: Date, notice: Bool = false) -> ChatMessage { Make.message(gid, sender: sender, at: d, notice: notice) }
    private func chatMsg(_ gid: String, _ d: Date) -> ChatMessage { chatMsg(gid, 7, d) }
    private func ids(_ items: [ChatListItem]) -> [String] {
        items.map { switch $0 { case .message(let m): m.gid; case .day: "day"; case .marker: "time"; case .typing: "typing" } }
    }

    func testDayDividerSitsAboveTheFirstMessageOfEachDay() {
        let items = ChatListRows.items([chatMsg("a", at(1, 9, 0)), chatMsg("b", at(1, 9, 1)), chatMsg("c", at(2, 8, 0))], markerGap: nil, calendar: cal)
        XCTAssertEqual(ids(items), ["day", "a", "b", "day", "c"])
        XCTAssertEqual(items[0], .day(cal.startOfDay(for: at(1, 9, 0))))
    }

    func testTimeMarkerAfterAPauseOnlyWhenTheStyleAsksForOne() {
        let ms = [chatMsg("a", at(1, 9, 0)), chatMsg("b", at(1, 9, 4)), chatMsg("c", at(1, 9, 20))]
        XCTAssertEqual(ids(ChatListRows.items(ms, markerGap: nil, calendar: cal)), ["day", "a", "b", "c"])
        XCTAssertEqual(ids(ChatListRows.items(ms, markerGap: 300, calendar: cal)), ["day", "a", "b", "time", "c"])
        // A day change wins over a marker.
        let next = ChatListRows.items([chatMsg("a", at(1, 23, 0)), chatMsg("b", at(2, 9, 0))], markerGap: 300, calendar: cal)
        XCTAssertEqual(ids(next), ["day", "a", "day", "b"])
    }

    func testRunsGroupOneSendersMessagesWithinFiveMinutes() {
        let rows = ChatListRows.rows([chatMsg("a", 1, at(1, 9, 0)), chatMsg("b", 1, at(1, 9, 3)), chatMsg("c", 1, at(1, 9, 5)), chatMsg("d", 2, at(1, 9, 6))],
                                     markerGap: nil, typing: false, calendar: cal)
        let flags = rows.compactMap { r in r.item.message.map { ($0.gid, r.firstOfRun, r.lastOfRun) } }
        XCTAssertEqual(flags.map(\.0), ["a", "b", "c", "d"])
        XCTAssertEqual(flags.map(\.1), [true, false, false, true])
        XCTAssertEqual(flags.map(\.2), [false, false, true, true])
    }

    func testAPauseBreaksARun() {
        let rows = ChatListRows.rows([chatMsg("a", 1, at(1, 9, 0)), chatMsg("b", 1, at(1, 9, 6))], markerGap: nil, typing: false, calendar: cal)
        XCTAssertEqual(rows.compactMap { $0.item.message }.count, 2)
        XCTAssertTrue(rows[1].lastOfRun)
        XCTAssertTrue(rows[2].firstOfRun)
    }

    func testNoticeAndSeparatorsStandApart() {
        let rows = ChatListRows.rows([chatMsg("a", 1, at(1, 9, 0)), chatMsg("n", 1, at(1, 9, 1), notice: true), chatMsg("b", 1, at(1, 9, 2)),
                                      chatMsg("c", 1, at(2, 9, 3))], markerGap: nil, typing: false, calendar: cal)
        let byId = Dictionary(uniqueKeysWithValues: rows.compactMap { r in r.item.message.map { ($0.gid, r) } })
        XCTAssertTrue(byId["a"]!.lastOfRun)
        XCTAssertTrue(byId["b"]!.firstOfRun, "the sender's next message after a notice shows who sent it")
        XCTAssertTrue(byId["b"]!.lastOfRun, "a day divider ends the run")
        XCTAssertTrue(byId["c"]!.firstOfRun)
    }

    func testTypingRowIsLastAndDoesNotBreakRuns() {
        let rows = ChatListRows.rows([chatMsg("a", 1, at(1, 9, 0)), chatMsg("b", 1, at(1, 9, 1))], markerGap: nil, typing: true, calendar: cal)
        XCTAssertEqual(rows.last?.item, .typing)
        XCTAssertEqual(rows.last?.id, "#typing")
        XCTAssertFalse(rows[1].lastOfRun)
        XCTAssertTrue(rows[2].lastOfRun)
    }

    func testRowIdsAreStablePerMessage() {
        let a = ChatListRows.rows([chatMsg("a", 1, at(1, 9, 0))], markerGap: nil, typing: false, calendar: cal)
        let b = ChatListRows.rows([chatMsg("z", 1, at(1, 8, 0)), chatMsg("a", 1, at(1, 9, 0))], markerGap: nil, typing: false, calendar: cal)
        XCTAssertTrue(a.map(\.id).contains("a"))
        XCTAssertTrue(b.map(\.id).contains("a"))
    }
}
