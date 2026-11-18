import CoreDomain
import XCTest
@testable import FeatureChat

/// Records the group and category calls; every one succeeds.
final class GroupRecordingRepository: StubChatRepository, @unchecked Sendable {
    var calls: [String] = []
    var settings: [(isPublic: Bool, adminInvite: Bool, committers: String)] = []
    var categories: [(gids: [String], category: String)] = []
    var created: [(memberIds: [Int], isPublic: Bool)] = []

    private func record(_ call: String) -> Outcome<Void> { calls.append(call); return .success(()) }
    override func renameGroupChat(accountId: String, chatGid: String, name: String) async -> Outcome<Void> { record("rename \(accountId) \(chatGid) \(name)") }
    override func dismissGroupChat(accountId: String, chatGid: String) async -> Outcome<Void> { record("dismiss \(chatGid)") }
    override func leaveGroupChat(accountId: String, chatGid: String) async -> Outcome<Void> { record("leave \(chatGid)") }
    override func addGroupMembers(accountId: String, chatGid: String, userIds: [Int]) async -> Outcome<Void> { record("add \(chatGid) \(userIds)") }
    override func removeGroupMembers(accountId: String, chatGid: String, userIds: [Int]) async -> Outcome<Void> { record("remove \(chatGid) \(userIds)") }
    override func setGroupAdmins(accountId: String, chatGid: String, userIds: [Int], admin: Bool) async -> Outcome<Void> { record("admins \(chatGid) \(userIds) \(admin)") }
    override func transferGroupOwnership(accountId: String, chatGid: String, userId: Int) async -> Outcome<Void> { record("transfer \(chatGid) \(userId)") }
    override func setGroupSettings(accountId: String, chatGid: String, isPublic: Bool, adminInvite: Bool, committers: String) async -> Outcome<Void> {
        settings.append((isPublic, adminInvite, committers)); return .success(())
    }
    override func setChatCategory(accountId: String, chatGids: [String], category: String) async -> Outcome<Void> {
        categories.append((chatGids, category)); return .success(())
    }
    override func createGroupChat(accountId: String, name: String, memberIds: [Int], isPublic: Bool) async -> Outcome<String> {
        created.append((memberIds, isPublic)); return .success("new")
    }
}

/// Ports of test/domain/chat/{manage_group_chat,group_settings,chat_category}_test.dart.
final class GroupUseCaseTests: XCTestCase {
    private let team = ChatConversation(accountId: "a", gid: "g", type: .group, name: "Team", adminIds: [7], ownerAccount: "owner")
    private var repo: GroupRecordingRepository!

    override func setUp() { repo = GroupRecordingRepository() }

    private func with(_ chat: ChatConversation, _ change: (inout ChatConversation) -> Void) -> ChatConversation { var c = chat; change(&c); return c }

    // MARK: rename / dismiss / leave

    func testOwnerAndAdminsRenameALiveGroup() {
        XCTAssertTrue(ChatGroupPolicy.canRename(team, selfUserId: 1, selfAccount: "owner"))
        XCTAssertTrue(ChatGroupPolicy.canRename(team, selfUserId: 7, selfAccount: "x"))
        XCTAssertFalse(ChatGroupPolicy.canRename(team, selfUserId: 2, selfAccount: "x"))
        XCTAssertFalse(ChatGroupPolicy.canRename(with(team) { $0.archived = true }, selfUserId: 7, selfAccount: "owner"))
        XCTAssertFalse(ChatGroupPolicy.canRename(with(team) { $0.type = .one2one }, selfUserId: 7, selfAccount: "owner"))
    }

    func testRenameSendsTrimmedNameRefusesBlankSkipsUnchanged() async {
        let rename = RenameGroupChat(repo)
        let o1 = await rename(team, "   ")
        XCTAssertNotNil(o1.failure)
        let o2 = await rename(team, " Team ")
        XCTAssertNotNil(o2.value)
        XCTAssertEqual(repo.calls, [])
        let o3 = await rename(team, "  New name ")
        XCTAssertNotNil(o3.value)
        XCTAssertEqual(repo.calls, ["rename a g New name"])
    }

    func testOnlyTheOwnerDismisses() async {
        XCTAssertTrue(ChatGroupPolicy.canDismiss(team, selfAccount: "owner"))
        XCTAssertFalse(ChatGroupPolicy.canDismiss(team, selfAccount: "admin"))
        XCTAssertFalse(ChatGroupPolicy.canDismiss(team, selfAccount: nil))
        XCTAssertFalse(ChatGroupPolicy.canDismiss(with(team) { $0.archived = true }, selfAccount: "owner"))
        let o4 = await DismissGroupChat(repo)(team, selfAccount: "admin")
        XCTAssertNotNil(o4.failure)
        XCTAssertEqual(repo.calls, [])
        let o5 = await DismissGroupChat(repo)(team, selfAccount: "owner")
        XCTAssertNotNil(o5.value)
        XCTAssertEqual(repo.calls, ["dismiss g"])
    }

    func testMembersLeaveTheOwnerCannot() async {
        XCTAssertTrue(ChatGroupPolicy.canLeave(team, selfAccount: "member"))
        XCTAssertFalse(ChatGroupPolicy.canLeave(team, selfAccount: "owner"))
        XCTAssertFalse(ChatGroupPolicy.canLeave(team, selfAccount: nil))
        XCTAssertFalse(ChatGroupPolicy.canLeave(with(team) { $0.archived = true }, selfAccount: "member"))
        let o6 = await LeaveGroupChat(repo)(team, selfAccount: "owner")
        XCTAssertNotNil(o6.failure)
        let o7 = await LeaveGroupChat(repo)(team, selfAccount: "member")
        XCTAssertNotNil(o7.value)
        XCTAssertEqual(repo.calls, ["leave g"])
    }

    // MARK: members

    func testWhoMayAddToALiveGroup() {
        XCTAssertTrue(ChatGroupPolicy.canAddMembers(team, selfUserId: 1, selfAccount: "owner"))
        XCTAssertTrue(ChatGroupPolicy.canAddMembers(team, selfUserId: 7, selfAccount: "x"))
        // Anyone who may post, unless inviting is kept to admins…
        XCTAssertTrue(ChatGroupPolicy.canAddMembers(team, selfUserId: 2, selfAccount: "x"))
        let adminsOnly = with(team) { $0.adminInvite = true }
        XCTAssertFalse(ChatGroupPolicy.canAddMembers(adminsOnly, selfUserId: 2, selfAccount: "x"))
        XCTAssertTrue(ChatGroupPolicy.canAddMembers(adminsOnly, selfUserId: 7, selfAccount: "x"))
        // …which a public group overrides.
        XCTAssertTrue(ChatGroupPolicy.canAddMembers(with(adminsOnly) { $0.isPublic = true }, selfUserId: 2, selfAccount: "x"))
        // Someone who may not post may not invite either.
        XCTAssertFalse(ChatGroupPolicy.canAddMembers(with(team) { $0.committers = "$ADMINS" }, selfUserId: 2, selfAccount: "x"))
        XCTAssertFalse(ChatGroupPolicy.canAddMembers(with(team) { $0.archived = true }, selfUserId: 7, selfAccount: "owner"))
    }

    func testAddSendsEachPersonOnceNothingForNoOne() async {
        let o8 = await AddGroupMembers(repo)(team, [])
        XCTAssertNotNil(o8.failure)
        XCTAssertEqual(repo.calls, [])
        let o9 = await AddGroupMembers(repo)(team, [3, 4, 3])
        XCTAssertNotNil(o9.value)
        XCTAssertEqual(repo.calls, ["add g [3, 4]"])
    }

    func testOnlyTheOwnerRemovesAndNeverThemself() async {
        XCTAssertTrue(ChatGroupPolicy.canRemoveMembers(team, selfAccount: "owner"))
        XCTAssertFalse(ChatGroupPolicy.canRemoveMembers(team, selfAccount: "admin"))
        let remove = RemoveGroupMember(repo)
        let o10 = await remove(team, 5, selfUserId: 7, selfAccount: "admin")
        XCTAssertNotNil(o10.failure)
        let o11 = await remove(team, 1, selfUserId: 1, selfAccount: "owner")
        XCTAssertNotNil(o11.failure)
        XCTAssertEqual(repo.calls, [])
        let o12 = await remove(team, 5, selfUserId: 1, selfAccount: "owner")
        XCTAssertNotNil(o12.value)
        XCTAssertEqual(repo.calls, ["remove g [5]"])
    }

    // MARK: settings, admins, owner

    func testCommittersReadAndWriteWhatXxdStores() {
        XCTAssertEqual(ChatCommitters.parse("").scope, .everyone)
        XCTAssertEqual(ChatCommitters.parse("$ALL").scope, .everyone)
        XCTAssertEqual(ChatCommitters.parse("$ADMINS").scope, .admins)
        let chosen = ChatCommitters.parse("5, 3")
        XCTAssertEqual(chosen.scope, .selected); XCTAssertEqual(chosen.userIds, [3, 5]); XCTAssertEqual(chosen.encode(), "3,5")
        XCTAssertEqual(ChatCommitters(.admins).encode(), "$ADMINS")
        XCTAssertEqual(ChatCommitters(.everyone).encode(), "")
    }

    func testSettingsOwnerAndAdminsEditAPublicGroupDropsAdminOnlyInvites() async {
        XCTAssertTrue(ChatGroupPolicy.canEditSettings(team, selfUserId: 1, selfAccount: "owner"))
        XCTAssertTrue(ChatGroupPolicy.canEditSettings(team, selfUserId: 7, selfAccount: "x"))
        XCTAssertFalse(ChatGroupPolicy.canEditSettings(team, selfUserId: 2, selfAccount: "x"))
        let o13 = await UpdateGroupSettings(repo)(team, isPublic: true, adminInvite: true, committers: ChatCommitters(.admins))
        XCTAssertNotNil(o13.value)
        XCTAssertEqual(repo.settings.last?.isPublic, true); XCTAssertEqual(repo.settings.last?.adminInvite, false)
        XCTAssertEqual(repo.settings.last?.committers, "$ADMINS")
    }

    func testChosenMembersNeedSomeoneChosen() async {
        let update = UpdateGroupSettings(repo)
        let o14 = await update(team, isPublic: false, adminInvite: true, committers: ChatCommitters(.selected))
        XCTAssertNotNil(o14.failure)
        XCTAssertTrue(repo.settings.isEmpty)
        _ = await update(team, isPublic: false, adminInvite: true, committers: ChatCommitters(.selected, [4, 2]))
        XCTAssertEqual(repo.settings.last?.adminInvite, true); XCTAssertEqual(repo.settings.last?.committers, "2,4")
    }

    func testAdminsAndOwnershipOnlyTheOwnerNeverForThemself() async {
        XCTAssertTrue(ChatGroupPolicy.canManageAdmins(team, selfAccount: "owner"))
        XCTAssertFalse(ChatGroupPolicy.canManageAdmins(team, selfAccount: "admin"))
        let o15 = await SetGroupAdmin(repo)(team, 5, admin: true, selfUserId: 7, selfAccount: "admin")
        XCTAssertNotNil(o15.failure)
        let o16 = await TransferGroupOwnership(repo)(team, 1, selfUserId: 1, selfAccount: "owner")
        XCTAssertNotNil(o16.failure)
        XCTAssertEqual(repo.calls, [])
        _ = await SetGroupAdmin(repo)(team, 5, admin: false, selfUserId: 1, selfAccount: "owner")
        _ = await TransferGroupOwnership(repo)(team, 5, selfUserId: 1, selfAccount: "owner")
        XCTAssertEqual(repo.calls, ["admins g [5] false", "transfer g 5"])
    }

    func testRightsSumUpThePolicy() {
        let owner = ChatGroupRights(team, selfUserId: 1, selfAccount: "owner")
        XCTAssertEqual([owner.rename, owner.dismiss, owner.addMembers, owner.removeMembers, owner.leave, owner.editSettings, owner.manageAdmins],
                       [true, true, true, true, false, true, true])
        let admin = ChatGroupRights(team, selfUserId: 7, selfAccount: "x")
        XCTAssertEqual([admin.rename, admin.dismiss, admin.addMembers, admin.removeMembers, admin.leave, admin.editSettings, admin.manageAdmins],
                       [true, false, true, false, true, true, false])
        XCTAssertFalse(admin.managesMembers)
        XCTAssertEqual(ChatGroupRights(with(team) { $0.type = .one2one }, selfUserId: 1, selfAccount: "owner"), ChatGroupRights())
    }

    func testCreateGroupPassesThePublicFlag() async {
        _ = await CreateGroupChat(repo)(accountId: "a", name: "G", memberIds: [2, 3, 2], isPublic: true)
        XCTAssertEqual(repo.created.first?.memberIds, [2, 3]); XCTAssertEqual(repo.created.first?.isPublic, true)
    }

    // MARK: categories

    private func chat(_ gid: String, category: String = "", unread: Int = 0, hidden: Bool = false) -> ChatConversation {
        ChatConversation(accountId: "a", gid: gid, type: .group, name: gid, unreadCount: unread, hidden: hidden, category: category)
    }

    func testCategoriesAreListedAToZWithTheirUnreadListedChatsOnly() {
        let categories = ListChatCategories()([chat("1", category: "work", unread: 2), chat("2", category: "Family", unread: 1),
                                               chat("3", category: "work", unread: 3), chat("4"), chat("5", category: "Old", hidden: true)])
        XCTAssertEqual(categories, [ChatCategory(name: "Family", unread: 1), ChatCategory(name: "work", unread: 5)])
    }

    func testFilingAChatSendsTheTrimmedNameNothingWhenUnchanged() async {
        let set = SetChatCategory(repo)
        _ = await set(chat("1", category: "Work"), " Work ")
        XCTAssertTrue(repo.categories.isEmpty)
        _ = await set(chat("1", category: "Work"), " Projects ")
        _ = await set(chat("1", category: "Work"), "")
        XCTAssertEqual(repo.categories.map(\.gids), [["1"], ["1"]]); XCTAssertEqual(repo.categories.map(\.category), ["Projects", ""])
    }

    func testRenamingOrDeletingRefilesEveryChatOfTheCategory() async {
        let rename = RenameChatCategory(repo)
        let chats = [chat("1", category: "Work"), chat("2"), chat("3", category: "Work")]
        _ = await rename(accountId: "a", chats: chats, from: "Work", to: "Projects")
        _ = await rename(accountId: "a", chats: chats, from: "Work", to: "")
        XCTAssertEqual(repo.categories.map(\.gids), [["1", "3"], ["1", "3"]]); XCTAssertEqual(repo.categories.map(\.category), ["Projects", ""])
        let o17 = await rename(accountId: "a", chats: chats, from: "None", to: "X")
        XCTAssertNotNil(o17.failure)
    }

    func testTheListFilterCombinesTabUnreadAndPickedTags() {
        let work = chat("1", category: "Work", unread: 2), quiet = chat("2", category: "Work")
        let home = chat("3", category: "Home", unread: 1), hidden = chat("4", unread: 5, hidden: true)
        func shown(_ f: ChatListFilter) -> [String] { [work, quiet, home, hidden].filter(f.matches).map(\.gid) }
        XCTAssertEqual(shown(ChatListFilter()), ["1", "2", "3"])
        XCTAssertEqual(shown(ChatListFilter(unreadOnly: true)), ["1", "3"])
        XCTAssertEqual(shown(ChatListFilter(categories: ["Work"])), ["1", "2"])
        XCTAssertEqual(shown(ChatListFilter(unreadOnly: true, categories: ["Work"])), ["1"])
        XCTAssertEqual(shown(ChatListFilter(tab: .direct)), [])
        XCTAssertFalse(ChatListFilter().isNarrowed)
        XCTAssertTrue(ChatListFilter(unreadOnly: true).isNarrowed)
    }
}
