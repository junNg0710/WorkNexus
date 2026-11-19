/// Not in the Flutter app: reply ideas in the voice of the user's role.
import CoreDomain
import XCTest
@testable import FeatureChat

final class ChatReplyRoleTests: XCTestCase {
    func testZenTaoCodesMapToVoices() {
        XCTAssertEqual(ChatReplyRole.fromZenTao("dev"), .developer)
        XCTAssertEqual(ChatReplyRole.fromZenTao(" QA "), .tester)
        XCTAssertEqual(ChatReplyRole.fromZenTao("td"), .techLead)
        XCTAssertEqual(ChatReplyRole.fromZenTao("po"), .productOwner)
        XCTAssertNil(ChatReplyRole.fromZenTao("others"))
        XCTAssertNil(ChatReplyRole.fromZenTao(nil))
    }

    func testAPickedRoleWinsOverZenTaoWhichWinsOverItsName() {
        let resolve = ResolveReplyRole()
        XCTAssertEqual(resolve(.techLead, zenTaoRole: "dev", roleName: "Developer"), ChatReplyRole.techLead.voice)
        XCTAssertEqual(resolve(.auto, zenTaoRole: "qa", roleName: nil), ChatReplyRole.tester.voice)
        XCTAssertEqual(resolve(.auto, zenTaoRole: "ops", roleName: "DevOps"), "a DevOps in a software team")
        XCTAssertNil(resolve(.auto, zenTaoRole: nil, roleName: nil))
    }

    func testThePromptSpeaksInTheRoleOnlyWhenThereIsOne() {
        let lead = SuggestChatReplies.prompt("[18/11 09:00] Lan (QA tester): login fails", selfName: "Jun", count: 3,
                                             selfRole: ChatReplyRole.techLead.voice)
        XCTAssertTrue(lead.contains("Jun is the tech lead"))
        XCTAssertTrue(lead.contains("role in brackets"))
        let plain = SuggestChatReplies.prompt("[18/11 09:00] Lan: hi", selfName: "Jun", count: 3)
        XCTAssertFalse(plain.contains("role"))
    }

    func testNamesCarryRolesOnlyWhenAsked() {
        let users = [1: ChatUser(accountId: "a", userId: 1, account: "jun", realname: "Jun", role: "td"),
                     2: ChatUser(accountId: "a", userId: 2, account: "lan", realname: "Lan", role: "qa"),
                     3: ChatUser(accountId: "a", userId: 3, account: "an", realname: "An", role: nil)]
        let withRoles = ChatAiPeople(users: users, selfUserId: 1) { ChatReplyRole.fromZenTao($0.role)?.englishName }
        XCTAssertEqual(withRoles.name(of: 2), "Lan (QA tester)")
        XCTAssertEqual(withRoles.name(of: 3), "An")
        XCTAssertEqual(withRoles.selfName, "Jun", "the user's own name stays plain: the prompt names their role itself")
        XCTAssertEqual(ChatAiPeople(users: users, selfUserId: 1).name(of: 2), "Lan")
    }
}
