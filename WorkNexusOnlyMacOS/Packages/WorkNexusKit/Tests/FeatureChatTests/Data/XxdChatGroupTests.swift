import CoreDomain
import XCTest
@testable import FeatureChat

/// Port of the group and category cases of test/data/chat/xxd_chat_repository_test.dart: each call's xxd request, and the
/// reply stored so the change shows. The fake server answers as the official one does (account 40 is signed in).
final class XxdChatGroupTests: RepositoryTestCase {
    /// When set, `chatsetconfig` is refused (a server older than it).
    let refuseConfig = Locked(false)

    override func setUp() async throws {
        try await super.setUp()
        let base = server.onRequest, refuseConfig = refuseConfig
        server.onRequest = { req in
            let params = req["params"]?.array ?? []
            let method = req["method"]?.string ?? ""
            let data: JSONValue?
            switch method {
            case "chatrename": data = ["gid": params[0], "name": params[1]]
            case "chatdismiss": data = ["gid": params[0], "dismissDate": .int(t0Server + 1000)]
            case "chatinvite":
                data = ["gid": params[0], "type": "group", "name": "Group", "members": .array([40] + (params[1].array ?? [])),
                        "adminInvite": "1", "public": true]
            case "chatsetconfig":
                if refuseConfig.current { return ["method": .string(method), "rid": req["rid"] ?? .null, "result": "fail", "message": "unknown method"] }
                var o = params[1].object!; o["gid"] = params[0]; data = .object(o)
            case "chatsetvisibility": data = ["gid": params[0], "public": params[1]]
            case "chatsetcommitters": data = ["gid": params[0], "committers": params[1]]
            case "chatsetcategory": data = ["gids": params[0], "category": params[1]]
            case "chataddadmins": data = ["gid": params[0], "admins": params[1]]
            case "chatchangeownership": data = ["gid": params[0], "type": "group", "name": "Group", "ownedBy": .string("u\(JS.toString(params[1]))")]
            case "chatleave": data = ["gid": params[0], "type": "group", "name": "Group", "members": [41]]
            // As if someone else's kick also removed this account (40); members as user objects.
            case "chatkick": data = ["gid": params[0], "type": "group", "name": "Group", "members": [["id": 41]]]
            default: return base?(req)
            }
            return ["method": .string(method), "rid": req["rid"] ?? .null, "result": "success", "data": data!]
        }
    }

    private func params(_ method: String) -> JSONValue? { server.requests(method).last?["params"] }

    func testRenamingAndDismissingAGroupFollowTheReplies() async throws {
        try await connectAndWait()
        let o1 = await repo.renameGroupChat(accountId: acc, chatGid: "g1", name: "Renamed")
        XCTAssertNotNil(o1.value)
        XCTAssertEqual(params("chatrename"), ["g1", "Renamed"])
        _ = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "g1")?.name == "Renamed" }

        let o2 = await repo.dismissGroupChat(accountId: acc, chatGid: "g1")
        XCTAssertNotNil(o2.value)
        XCTAssertEqual(params("chatdismiss"), ["g1"])
        _ = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "g1")?.archived == true }
    }

    func testAddingAndRemovingMembersFollowTheReplies() async throws {
        try await connectAndWait()
        let o3 = await repo.addGroupMembers(accountId: acc, chatGid: "g1", userIds: [41, 42])
        XCTAssertNotNil(o3.value)
        XCTAssertEqual(params("chatinvite"), ["g1", [41, 42]])
        let invited = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "g1")?.name == "Group" }
        let group = try XCTUnwrap(byGid(invited, "g1"))
        XCTAssertFalse(group.archived); XCTAssertTrue(group.adminInvite); XCTAssertTrue(group.isPublic)

        let o4 = await repo.removeGroupMembers(accountId: acc, chatGid: "g1", userIds: [40])
        XCTAssertNotNil(o4.value)
        XCTAssertEqual(params("chatkick"), ["g1", [40]])
        _ = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "g1")?.archived == true }
    }

    func testGroupSettingsAdminsAndOwnerFollowTheReplies() async throws {
        try await connectAndWait()
        let r = await repo.setGroupSettings(accountId: acc, chatGid: "g1", isPublic: true, adminInvite: false, committers: "$ADMINS")
        XCTAssertNotNil(r.value)
        XCTAssertEqual(params("chatsetconfig"), ["g1", ["public": true, "adminInvite": false, "committers": "$ADMINS"]])
        _ = try await eventually(repo.watchConversations(accountId: acc)) {
            self.byGid($0, "g1")?.isPublic == true && self.byGid($0, "g1")?.committers == "$ADMINS"
        }

        let o5 = await repo.setGroupAdmins(accountId: acc, chatGid: "g1", userIds: [41], admin: true)
        XCTAssertNotNil(o5.value)
        XCTAssertEqual(params("chataddadmins"), ["g1", [41], 40])
        _ = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "g1")?.adminIds.contains(41) == true }

        let o6 = await repo.transferGroupOwnership(accountId: acc, chatGid: "g1", userId: 41)
        XCTAssertNotNil(o6.value)
        XCTAssertEqual(params("chatchangeownership"), ["g1", 41])
        _ = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "g1")?.ownerAccount == "u41" }
    }

    func testOlderServersTakeVisibilityAndCommittersOneByOne() async throws {
        refuseConfig.with { $0 = true }
        try await connectAndWait()
        let r = await repo.setGroupSettings(accountId: acc, chatGid: "g1", isPublic: true, adminInvite: true, committers: "3,5")
        XCTAssertNotNil(r.value)
        XCTAssertEqual(params("chatsetvisibility"), ["g1", true])
        XCTAssertEqual(params("chatsetcommitters"), ["g1", "3,5"])
        _ = try await eventually(repo.watchConversations(accountId: acc)) {
            self.byGid($0, "g1")?.isPublic == true && self.byGid($0, "g1")?.committers == "3,5"
        }
    }

    func testFilingChatsUnderACategoryFollowsTheReply() async throws {
        try await connectAndWait()
        let o7 = await repo.setChatCategory(accountId: acc, chatGids: ["g1", "31&40"], category: "Work")
        XCTAssertNotNil(o7.value)
        XCTAssertEqual(params("chatsetcategory"), [["g1", "31&40"], "Work"])
        _ = try await eventually(repo.watchConversations(accountId: acc)) { $0.allSatisfy { $0.category == "Work" } }
        // Filed from another client: pushed.
        server.current.push(["method": "chatSetCategory", "result": "success", "data": ["gids": ["g1"], "category": ""]])
        _ = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "g1")?.category == "" }
    }

    func testLeavingAGroupTakesItOffTheList() async throws {
        try await connectAndWait()
        let o8 = await repo.leaveGroupChat(accountId: acc, chatGid: "g1")
        XCTAssertNotNil(o8.value)
        XCTAssertEqual(params("chatleave"), ["g1"])
        _ = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "g1")?.archived == true }
    }

    func testCreatingAPublicGroupSendsTheFlag() async throws {
        try await connectAndWait()
        _ = await repo.createGroupChat(accountId: acc, name: "Open", memberIds: [41, 42], isPublic: true)
        let p = try XCTUnwrap(params("chatcreate")?.array)
        XCTAssertEqual(Array(p[1...]), ["Open", "group", [40, 41, 42], 0, true])
    }

    func testGroupFlagsAreReadFromTheChatList() async throws {
        server.chats = [["gid": "g1", "type": "group", "name": "Team", "adminInvite": "1", "public": 0, "category": "Projects",
                         "admins": [41], "ownedBy": "demo"]]
        _ = await repo.connect(accountId: acc)
        let chats = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "g1") != nil }
        let g = try XCTUnwrap(byGid(chats, "g1"))
        XCTAssertTrue(g.adminInvite); XCTAssertFalse(g.isPublic); XCTAssertEqual(g.category, "Projects"); XCTAssertEqual(g.adminIds, [41])
    }
}
