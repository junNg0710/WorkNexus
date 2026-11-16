import CoreDomain
import XCTest
@testable import FeatureNotifications

/// Ports of test/domain/{parse_notification_event,filter_self_notifications,find_new_notifications,
/// notification_usecases}_test.dart.
final class NotificationUseCaseTests: XCTestCase {
    private func n(_ id: String, _ summary: String = "JunNg assigned Bug", account: String = "a1", read: Bool = false,
                   at: Date? = nil) -> ZenTaoNotification {
        ZenTaoNotification(accountId: account, id: id, summary: summary, objectType: "task", objectId: "12974", read: read, createdAt: at)
    }
    private func date(_ d: Int, _ h: Int, _ m: Int = 0, month: Int = 10) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: d, hour: h, minute: m))!
    }

    // MARK: ParseNotificationEvent

    func testParsesEnglishEvent() {
        let parse = ParseNotificationEvent()
        XCTAssertEqual(parse("JunNg-VN-Flutter assigned Bug"), NotificationEvent(actor: "JunNg-VN-Flutter", action: .assigned))
        XCTAssertEqual(parse("Luci-VN-Flutter finished Task"), NotificationEvent(actor: "Luci-VN-Flutter", action: .finished))
    }

    func testParsesChineseEventWithVerbRightAfterTheName() {
        let parse = ParseNotificationEvent()
        XCTAssertEqual(parse("Thanh-VN-Flutter指派了Bug"), NotificationEvent(actor: "Thanh-VN-Flutter", action: .assigned))
        XCTAssertEqual(parse("Justin-VNTest关闭了任务"), NotificationEvent(actor: "Justin-VNTest", action: .closed))
    }

    func testKeepsNameWithSpacesWholeAndIgnoresVerbInsideName() {
        let parse = ParseNotificationEvent()
        XCTAssertEqual(parse("Nguyen Van An resolved Bug"), NotificationEvent(actor: "Nguyen Van An", action: .resolved))
        XCTAssertEqual(parse("closedbeta assigned Bug"), NotificationEvent(actor: "closedbeta", action: .assigned))
    }

    func testTextWithoutKnownActionIsLeftAlone() {
        let parse = ParseNotificationEvent()
        XCTAssertNil(parse("JunNg mentioned you"))
        XCTAssertNil(parse("assigned Bug"))
        XCTAssertNil(parse("JunNg assigned"))
        XCTAssertNil(parse(""))
    }

    // MARK: FilterSelfNotifications

    private var accounts: [Account] {
        [Account(id: "a1", workspaceId: "ws1", providerType: .zentao, handle: "Sunshine_VN_Golang"),
         Account(id: "a2", workspaceId: "ws1", providerType: .zentao, handle: "Dan")]
    }
    private let realnames = ["a1": "Son Vu", "a2": "Dan Nguyen"]

    private func filtered(_ items: [ZenTaoNotification]) -> [String] {
        FilterSelfNotifications()(items, accounts: accounts, realnamesByAccountId: realnames).map(\.id)
    }

    func testFiltersSelfByHandleAndRealnameCaseInsensitively() {
        XCTAssertEqual(filtered([n("1", "Sunshine_VN_Golang started Task"), n("2")]), ["2"])
        XCTAssertEqual(filtered([n("1", "Son Vu started Task"), n("2")]), ["2"])
        XCTAssertEqual(filtered([n("1", "sunshine_vn_golang started Task"), n("2", "son vu closed Bug"), n("3")]), ["3"])
    }

    func testFiltersChineseSummariesMatchingUserName() {
        XCTAssertEqual(filtered([n("1", "Sunshine_VN_Golang开始了Task"), n("2", "Son Vu指派了Bug"), n("3", "Thanh指派了Bug")]), ["3"])
    }

    func testDoesNotFilterAnotherUserWithPrefixName() {
        XCTAssertEqual(filtered([n("1", "Daniel assigned Bug", account: "a2"), n("2", "Dan assigned Bug", account: "a2")]), ["1"])
    }

    func testFallbackFiltersUnknownVerbStartingWithHandle() {
        XCTAssertEqual(filtered([n("1", "Sunshine_VN_Golang pinged the channel"), n("2", "JunNg pinged the channel")]), ["2"])
    }

    func testReturnsOriginalListWhenNotificationsOrAccountsAreEmpty() {
        XCTAssertTrue(FilterSelfNotifications()([], accounts: accounts).isEmpty)
        let items = [n("1", "Sunshine_VN_Golang started Task")]
        XCTAssertEqual(FilterSelfNotifications()(items, accounts: []), items)
    }

    // MARK: FindNewNotifications

    private func z(_ id: String, account: String = "zt", read: Bool = false, minute: Int = 0) -> ZenTaoNotification {
        ZenTaoNotification(accountId: account, id: id, summary: "JunNg assigned Bug", read: read, createdAt: date(20, 10, minute))
    }

    func testFirstListIsTheBacklogNotNews() {
        let r = FindNewNotifications()(seen: nil, current: [z("1"), z("2")])
        XCTAssertTrue(r.fresh.isEmpty)
        XCTAssertEqual(r.seen, ["zt:1", "zt:2"])
    }

    func testRaisesUnreadOnesNotSeenBeforeNewestFirst() {
        let r = FindNewNotifications()(seen: ["zt:1"], current: [z("1"), z("2", minute: 5), z("3", minute: 9)])
        XCTAssertEqual(r.fresh.map(\.id), ["3", "2"])
        XCTAssertEqual(r.seen, ["zt:1", "zt:2", "zt:3"])
    }

    func testNotOneAlreadyReadElsewhereAndAccountsAreTold() {
        XCTAssertTrue(FindNewNotifications()(seen: ["zt:1"], current: [z("1"), z("2", read: true)]).fresh.isEmpty)
        let r = FindNewNotifications()(seen: ["zt:1", "other:9"], current: [z("1", account: "other")])
        XCTAssertEqual(r.fresh.map(\.accountId), ["other"])
    }

    func testAnAccountsFirstNotificationsAreItsBacklog() {
        let find = FindNewNotifications()
        let empty = find(seen: nil, current: [])
        let fetched = find(seen: empty.seen, current: [z("1"), z("2")])
        XCTAssertTrue(fetched.fresh.isEmpty)
        let added = find(seen: fetched.seen, current: [z("1"), z("2"), z("7", account: "new")])
        XCTAssertTrue(added.fresh.isEmpty)
        let later = find(seen: added.seen, current: [z("1"), z("2"), z("7", account: "new"), z("3")])
        XCTAssertEqual(later.fresh.map(\.id), ["3"])
    }

    func testOneThatDroppedOffAndCameBackIsNotNews() {
        let find = FindNewNotifications()
        let afterGap = find(seen: ["zt:1", "zt:2"], current: [z("1")])
        XCTAssertTrue(find(seen: afterGap.seen, current: [z("1"), z("2")]).fresh.isEmpty)
    }

    // MARK: GroupNotificationsByDay / PlanDesktopAlerts

    func testGroupsByDayNewestFirst() {
        let items = [n("old", at: date(5, 11)), n("new", read: true, at: date(9, 11)), n("newer", at: date(9, 15)), n("undated")]
        let days = GroupNotificationsByDay()(items)
        XCTAssertEqual(days.map(\.day), [Calendar.current.startOfDay(for: date(9, 0)), Calendar.current.startOfDay(for: date(5, 0)), nil])
        XCTAssertEqual(days[0].items.map(\.id), ["newer", "new"])
        XCTAssertEqual(GroupNotificationsByDay()(items, unreadOnly: true)[0].items.map(\.id), ["newer"])
        XCTAssertTrue(GroupNotificationsByDay()([]).isEmpty)
    }

    func testDesktopAlertPlan() {
        let plan = PlanDesktopAlerts()
        XCTAssertEqual(plan([]), .none)
        let three = (1...3).map { z("\($0)") }
        XCTAssertEqual(plan(three), .each(three))
        let four = (1...4).map { z("\($0)") }
        XCTAssertEqual(plan(four), .count(4, first: four[0]))
    }

    // MARK: Payload / text

    func testAlertPayloadRoundTrips() {
        let one = NotificationAlertPayload(notificationId: "12", accountId: "zt-a")
        XCTAssertEqual(NotificationAlertPayload(json: one.json), one)
        let count = NotificationAlertPayload(notificationId: nil)
        XCTAssertEqual(count.json, "{\"zn\":null}")
        XCTAssertEqual(NotificationAlertPayload(json: count.json), count)
        XCTAssertNil(NotificationAlertPayload(json: "{\"other\":1}"))
        XCTAssertNil(NotificationAlertPayload(json: "not json"))
    }

    func testEventTextUsesTheAppsLanguage() {
        let bug = ZenTaoNotification(accountId: "a", id: "1", summary: "Thanh指派了Bug", objectType: "bug")
        XCTAssertEqual(NotificationStrings.eventText(bug, language: "en"), "Thanh assigned Bug")
        XCTAssertEqual(NotificationStrings.eventText(bug, language: "vi"), "Thanh đã giao Bug")
        let unknown = ZenTaoNotification(accountId: "a", id: "2", summary: "JunNg mentioned you", objectType: "bug")
        XCTAssertEqual(NotificationStrings.eventText(unknown, language: "en"), "JunNg mentioned you")
        let noObject = ZenTaoNotification(accountId: "a", id: "3", summary: "JunNg assigned Doc", objectType: "doc")
        XCTAssertEqual(NotificationStrings.eventText(noObject, language: "en"), "JunNg assigned Doc")
    }
}
