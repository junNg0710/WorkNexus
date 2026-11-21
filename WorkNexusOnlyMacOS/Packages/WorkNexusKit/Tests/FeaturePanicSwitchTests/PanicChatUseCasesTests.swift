import CoreDomain
import Foundation
import XCTest
@testable import FeaturePanicSwitch

/// Ported from: test/features/panic_switch/panic_chat_usecases_test.dart + find_panic_switch_account_test.dart
final class PanicChatUseCasesTests: XCTestCase {
    private func chat(_ gid: String, _ name: String, _ kind: PanicChatRef.Kind) -> PanicChatRef {
        PanicChatRef(gid: gid, kind: kind, name: name)
    }

    private func person(_ id: Int, _ name: String) -> PanicPerson { PanicPerson(userId: id, account: "u\(id)", realname: name) }

    func testSendsTheStickerBytesUnderTheReservedName() async {
        let chats = FakeChatGateway()
        let send = SendPanicSticker(chats, FakeSticker(result: .success(Data([1, 2]))))
        let result = await send(trigger: .release, accountId: "a1", chatGid: "g1")
        _ = await send(trigger: .demo, accountId: "a1", chatGid: "dm")

        XCTAssertNotNil(result.value)
        XCTAssertEqual(chats.sent, [.init(accountId: "a1", chatGid: "g1", name: "worknexus-thayvo-v1.png", bytes: Data([1, 2]),
                                          mimeType: "image/png"),
                                    .init(accountId: "a1", chatGid: "dm", name: "worknexus-thayvo-demo-v1.png", bytes: Data([1, 2]),
                                          mimeType: "image/png")])
    }

    func testReturnsTheFailureWhenTheStickerCannotBeLoaded() async {
        let chats = FakeChatGateway()
        let result = await SendPanicSticker(chats, FakeSticker(result: .failure(.storage("missing"))))(trigger: .release,
                                                                                                     accountId: "a1", chatGid: "g1")

        XCTAssertEqual(result.failure, .storage("missing"))
        XCTAssertTrue(chats.sent.isEmpty)
    }

    func testPickDefaultPanicGroupFindsTheTeamGroupByName() {
        let pick = PickDefaultPanicGroup()
        XCTAssertEqual(pick([chat("dm", "VN Mobile Tester", .direct), chat("g2", " vn mobile tester ", .group)]), "g2")
        XCTAssertEqual(pick([chat("g3", "VN Mobile+Tester", .group)]), "g3")
        XCTAssertNil(pick([chat("g1", "Other", .group)]))
    }

    func testShouldSendPanicNeedsAChatAndRespectsTheDebounce() {
        let should = ShouldSendPanic()
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let config = PanicSwitchConfig(chatGid: "g1")
        XCTAssertFalse(should(trigger: .release, config: PanicSwitchConfig(), now: now))
        XCTAssertTrue(should(trigger: .release, config: config, now: now))
        // The demo needs demo mode and its own chat.
        XCTAssertFalse(should(trigger: .demo, config: config, now: now))
        var demo = config; demo.demoMode = true
        XCTAssertFalse(should(trigger: .demo, config: demo, now: now))
        demo.demoChatGid = "dm"
        XCTAssertTrue(should(trigger: .demo, config: demo, now: now))
        XCTAssertFalse(should(trigger: .release, config: config, now: now, lastSentAt: now.addingTimeInterval(-30)))
        // Turned off, nothing is sent.
        var off = demo; off.enabled = false
        XCTAssertFalse(should(trigger: .release, config: off, now: now))
        XCTAssertFalse(should(trigger: .demo, config: off, now: now))
    }

    func testListPanicChatsOffersYourselfThenGroupsAndDirectChats() {
        let chats = ListPanicChats()(
            [chat("g2", "beta", .group),
             PanicChatRef(gid: "dm", kind: .direct, name: "", peerUserId: 2),
             chat("bot", "Bot", .other),
             PanicChatRef(gid: "cloud", kind: .direct, name: "", peerUserId: 1, isMyCloud: true),
             PanicChatRef(gid: "hid", kind: .group, name: "Hidden", hidden: true),
             chat("g1", "Alpha", .group)],
            [1: person(1, "Me"), 2: person(2, "Zoe")], selfTitle: "Myself")

        XCTAssertEqual(chats.map(\.chat.gid), ["cloud", "g1", "g2", "dm"])
        XCTAssertEqual(chats.map(\.title), ["Myself", "Alpha", "beta", "Zoe"])
    }

    func testLoadPanicGroupMembersNamesTheMembersWithoutTheUser() async {
        let chats = FakeChatGateway()
        chats.people = [person(1, "Me"), person(2, "Zoe"), person(3, "An")]
        chats.me = 1
        chats.members = .success([1, 2, 3, 9])

        let result = await LoadPanicGroupMembers(chats)(accountId: "a1", chatGid: "g1")

        XCTAssertEqual(result.value?.map(\.userId), [3, 2])
    }

    func testFindsTheZenTaoAccountOnTheSupportedServer() {
        let match = panicAccount("z2", .zentao, "HTTPS://zentao.oasoft.xyz:4433/zentao/")
        XCTAssertEqual(FindPanicSwitchAccount()([panicAccount("z1", .zentao, "https://other.example/zentao"),
                                                 panicAccount("g", .github, "https://zentao.oasoft.xyz:4433/zentao"), match]), match)
    }

    func testFindPanicSwitchAccountIsNilWhenNoAccountMatches() {
        XCTAssertNil(FindPanicSwitchAccount()([panicAccount("z1", .zentao, "https://other.example")]))
    }

    func testTheTeamIsWhoeverHasTheTeamsGroupAmongTheirChats() {
        XCTAssertTrue(IsInPanicTeam()([PanicChatRef(gid: "g", kind: .group, name: "VN Mobile+Tester")]))
        XCTAssertTrue(IsInPanicTeam()([PanicChatRef(gid: "g", kind: .group, name: "vn mobile + tester", hidden: true)]), "hidden still counts")
        XCTAssertFalse(IsInPanicTeam()([PanicChatRef(gid: "g", kind: .group, name: "VN Mobile Team")]))
        XCTAssertFalse(IsInPanicTeam()([PanicChatRef(gid: "d", kind: .direct, name: "VN Mobile+Tester")]), "only a group counts")
        XCTAssertFalse(IsInPanicTeam()([]))
    }
}
