import CoreDomain
import XCTest
@testable import FeatureChat

@MainActor
final class ChatShellModelTests: XCTestCase {
    private func make(_ repo: ShellFakeRepository = ShellFakeRepository()) -> (ChatShellModel, ShellFakeRepository) {
        (ChatShellModel(accountId: "a", selfAccount: "me", repository: repo), repo)
    }

    func testAskingToTrustHappensOncePerFingerprint() {
        let (model, _) = make()
        model.apply(status: .needsTrust(host: "h", fingerprint: "AA", subject: "s", issuer: "i"))
        XCTAssertTrue(model.showTrust)
        model.showTrust = false      // "Not now"
        model.apply(status: .needsTrust(host: "h", fingerprint: "AA", subject: "s", issuer: "i"))
        XCTAssertFalse(model.showTrust, "the same certificate is not put again")
        model.apply(status: .needsTrust(host: "h", fingerprint: "BB", subject: "s", issuer: "i"))
        XCTAssertTrue(model.showTrust, "a different one is")
        model.apply(status: .online(selfUserId: 1))
        XCTAssertFalse(model.showTrust)
        model.apply(status: .needsTrust(host: "h", fingerprint: "BB", subject: "s", issuer: "i"))
        XCTAssertTrue(model.showTrust, "settled in between: asks again")
    }

    func testTrustCallsTheUseCaseAndReportsFailures() async {
        let (model, repo) = make()
        model.apply(status: .needsTrust(host: "h", fingerprint: "AA", subject: "s", issuer: "i"))
        let ok = await model.trust(fingerprint: "AA")
        XCTAssertNil(ok)
        XCTAssertEqual(repo.trusted, ["AA"])
        XCTAssertFalse(model.showTrust)
        repo.trustResult = .failure(.network("down"))
        model.showTrust = true
        let failed = await model.trust(fingerprint: "AA")
        XCTAssertEqual(failed, "Couldn't complete that: down")
        XCTAssertTrue(model.showTrust, "the dialog stays for a retry")
    }

    func testSelectingAChatBuildsItsSessionOnceTheConversationIsKnown() async {
        let (model, repo) = make()
        model.select("g1")
        XCTAssertNil(model.thread, "the chat is not known yet")
        model.apply(conversations: [ShellMake.chat("g1", name: "Team")])
        XCTAssertEqual(model.thread?.state.chatGid, "g1")
        await ShellMake.expectEventually { repo.refreshCalls == ["g1"] && repo.markReadCalls == ["g1"] }
        await ShellMake.expectEventually { model.thread?.memberCount == 7 }
    }

    func testTheOpenSessionFollowsChatUsersAndSelf() {
        let (model, _) = make()
        model.apply(conversations: [ShellMake.chat("g1", name: "Team")])
        model.select("g1")
        model.apply(users: [ShellMake.user(2, "Bình")])
        model.apply(selfUserId: 2)
        XCTAssertEqual(model.thread?.state.users[2]?.realname, "Bình")
        XCTAssertEqual(model.thread?.state.selfUserId, 2)
        model.apply(conversations: [ShellMake.chat("g1", name: "Renamed"), ShellMake.chat("g2", name: "Other")])
        XCTAssertEqual(model.thread?.state.chat.name, "Renamed")
    }

    func testSwitchingChatsReplacesTheSession() {
        let (model, _) = make()
        model.apply(conversations: [ShellMake.chat("g1", name: "A"), ShellMake.chat("g2", name: "B")])
        model.select("g1")
        let first = model.thread
        model.select("g2")
        XCTAssertEqual(model.thread?.state.chatGid, "g2")
        XCTAssertFalse(model.thread === first)
    }

    func testSearchBoxPicksWithTheArrowsAndEnterOpens() {
        let (model, _) = make()
        model.apply(conversations: [ShellMake.chat("a", name: "Alpha", at: 3), ShellMake.chat("b", name: "Alps", at: 2), ShellMake.chat("c", name: "Beta", at: 1)])
        model.moveHighlight(1)
        XCTAssertNil(model.highlightedGid, "the full list is not a pick")
        model.setSearch("al")
        XCTAssertEqual(model.listed.map(\.id), ["a", "b"])
        model.moveHighlight(1); model.moveHighlight(1)
        XCTAssertEqual(model.highlightedGid, "b")
        model.setSearch("alps")
        XCTAssertNil(model.highlightedGid, "typing starts the pick over")
        model.openHighlighted()
        XCTAssertEqual(model.selectedGid, "b", "Enter opens the first listed when none is picked")
    }

    func testTypingFollowsSignalsAndLapses() async {
        let (model, _) = make()
        let now = Date()
        model.apply(typing: ChatTypingSignal(chatGid: "g", userId: 2, typing: true), now: now)
        XCTAssertEqual(model.typing(in: "g"), [2])
        model.apply(typing: ChatTypingSignal(chatGid: "g", userId: 2, typing: false), now: now)
        XCTAssertEqual(model.typing(in: "g"), [])
        model.apply(selfUserId: 9)
        model.apply(typing: ChatTypingSignal(chatGid: "g", userId: 9, typing: true), now: now)
        XCTAssertEqual(model.typing(in: "g"), [], "own echo is ignored")
        model.apply(typing: ChatTypingSignal(chatGid: "g", userId: 3, typing: true), now: now.addingTimeInterval(-TypingRoster.ttl + 0.1))
        await ShellMake.expectEventually { model.typing(in: "g").isEmpty }   // the entry lapses on its own
    }

    func testOpeningADirectChatSelectsIt() async {
        let (model, repo) = make()
        model.apply(conversations: [ShellMake.chat("direct-1", type: .one2one, peer: 2)])
        model.tab = .groups; model.setSearch("zzz")
        let ok = await model.openDirectChat(userId: 2)
        XCTAssertTrue(ok)
        XCTAssertEqual(model.selectedGid, "direct-1")
        XCTAssertEqual(model.tab, .all)
        XCTAssertEqual(model.searchText, "")
        repo.openDirectResult = .failure(.network("offline"))
        let failed = await model.openDirectChat(userId: 3)
        XCTAssertFalse(failed)
        XCTAssertEqual(model.toasts.toasts.first?.message, "Couldn't complete that: offline")
    }

    func testPinningCallsTheRepository() async {
        let (model, repo) = make()
        model.setStarred(ShellMake.chat("g"), true)
        await ShellMake.expectEventually { !repo.starredCalls.isEmpty }
        XCTAssertEqual(repo.starredCalls.first?.0, "g")
        XCTAssertEqual(repo.starredCalls.first?.1, true)
    }

    func testStreamsFeedTheModel() async {
        let (model, repo) = make()
        model.start()
        await ShellMake.expectEventually { repo.conversationsCont != nil && repo.statusCont != nil && repo.usersCont != nil }
        repo.statusCont?.yield(.online(selfUserId: 4))
        repo.usersCont?.yield([ShellMake.user(4, "An")])
        repo.conversationsCont?.yield([ShellMake.chat("g", name: "Team", unread: 2)])
        await ShellMake.expectEventually { model.conversationsLoaded && model.users[4] != nil && model.status == .online(selfUserId: 4) }
        XCTAssertEqual(model.unread(.all), 2)
        model.stop()
    }

    func testIncomingGroupRequiresTwoPeopleAndAName() async {
        let (model, _) = make()
        let ok = await model.createGroup(name: "G", memberIds: [1])
        XCTAssertFalse(ok)
        XCTAssertEqual(model.toasts.toasts.count, 1, "the use case's validation failure is reported")
    }
}
