import CoreDomain
import XCTest
@testable import CoreTools

@MainActor
final class NavControllerTests: XCTestCase {
    private func nav() -> AppNavController { AppNavController { _ in "default" } }
    private func acct(_ id: String, _ p: ProviderType = .gitlab) -> Account { Account(id: id, workspaceId: "w", providerType: p, handle: id) }

    func testCloseTicketForgetsThePlacesWholeHistoryButNotOthers() {
        let n = nav()
        n.select(.account("a")); n.openTicket("1"); n.openTicket("2")
        n.select(.account("b")); n.openTicket("9")
        n.select(.account("a"))
        XCTAssertEqual(n.openTicketId, "2")
        XCTAssertTrue(n.canGoBackTicket)
        n.goBackTicket(); XCTAssertEqual(n.openTicketId, "1")
        n.goBackTicket(); XCTAssertEqual(n.openTicketId, "1", "back stops at the first ticket")
        n.openTicket("3"); n.closeTicket()
        XCTAssertNil(n.openTicketId)
        n.select(.account("b")); XCTAssertEqual(n.openTicketId, "9")
        n.closeAllTickets(); XCTAssertNil(n.openTicketId)
    }

    func testEditorPrefillLivesOnlyAsLongAsTheEditorItWasOpenedWith() {
        let n = nav(), prefill = TicketEditorPrefill(title: "Login fails", bodyHtml: "<p>steps</p>")
        n.openEditor(.newBug(accountId: "a"), prefill: prefill)
        XCTAssertEqual(n.state.editorPrefill, prefill)
        n.openEditor(.newTask(accountId: "a"))
        XCTAssertNil(n.state.editorPrefill, "an ordinary new ticket starts empty")
        n.openEditor(.newBug(accountId: "a"), prefill: prefill); n.closeEditor()
        XCTAssertNil(n.state.editorPrefill)
    }

    func testEditorAndMiniAppCloseTheNotificationsPanel() {
        let n = nav(); var closed = 0
        n.closeNotifications = { closed += 1 }
        n.openEditor(.newBug(accountId: "a")); XCTAssertEqual(closed, 1)
        n.openMiniApp("m"); XCTAssertEqual(closed, 2)
        XCTAssertNil(n.state.editor, "a mini app drops the editor")
        n.openMiniApp(nil); XCTAssertEqual(closed, 2)
    }

    func testDefaultAppRules() {
        let n = nav()
        n.selectDefaultAppIfApplicable(accounts: [acct("gl"), acct("zt", .zentao)])
        XCTAssertEqual(n.state.rail, .account("zt"), "ZenTao sorts first")
        // an existing account stays
        n.select(.account("gl")); n.selectDefaultAppIfApplicable(accounts: [acct("gl"), acct("zt", .zentao)])
        XCTAssertEqual(n.state.rail, .account("gl"))
        // the dashboard the user picked, settings and the chat are theirs
        n.select(.workspace); n.selectDefaultAppIfApplicable(accounts: [acct("gl")]); XCTAssertEqual(n.state.rail, .workspace)
        n.select(.settings); n.selectDefaultAppIfApplicable(accounts: [acct("gl")]); XCTAssertEqual(n.state.rail, .settings)
        // an account that left its workspace gives way
        n.select(.account("gone")); n.selectDefaultAppIfApplicable(accounts: [acct("gl")]); XCTAssertEqual(n.state.rail, .account("gl"))
        // the editor is not yanked away
        n.select(.account("gone")); n.openEditor(.newBug(accountId: "gl"))
        n.selectDefaultAppIfApplicable(accounts: [acct("gl")]); XCTAssertNotNil(n.state.editor)
        XCTAssertEqual(n.state.rail, .account("gone"))
    }

    func testWorkspaceSwitchAndAccountRemoval() {
        let n = nav()
        n.select(.account("a")); n.openTicket("1")
        n.onWorkspaceSwitched(newAccounts: [acct("b")])
        XCTAssertEqual(n.state.rail, .account("b")); XCTAssertTrue(n.state.ticketHistories.isEmpty)
        n.onAccountRemoved("b")
        XCTAssertEqual(n.state.rail, .workspace); XCTAssertNil(n.state.locations["b"])
    }

    func testCollapsedPanesUseTheDartKeyFormat() {
        let n = nav()
        let key = AppNavController.paneKey("acc", "zentao.docs")
        XCTAssertEqual(key, "acc|zentao.docs")
        n.setPane(key, collapsed: true); XCTAssertTrue(n.isPaneCollapsed(key))
        n.setPane(key, collapsed: false); XCTAssertFalse(n.isPaneCollapsed(key))
    }

    /// Dart `BoardSortController.sortBy`: the same field flips its direction, another starts in its own default one.
    func testPickingTheBoardSortFieldAgainFlipsItsDirection() {
        let n = nav()
        XCTAssertEqual(n.boardSort, .boardDefault)
        n.sortBoardCards(by: .priority); XCTAssertEqual(n.boardSort, TicketSort(.priority, descending: true))
        n.sortBoardCards(by: .updated); XCTAssertEqual(n.boardSort, TicketSort(.updated, descending: true))
        n.sortBoardCards(by: .title); XCTAssertEqual(n.boardSort, TicketSort(.title))
        n.sortBoardCards(by: .title); XCTAssertEqual(n.boardSort, TicketSort(.title, descending: true))
    }

    /// Going from Tasks to Bugs and back finds each on the scope it was left on (an execution, a product), so neither has
    /// to pick a scope and read its board again.
    func testEachSectionComesBackOnTheScopeItWasLeftOn() {
        let n = nav()
        n.select(.account("zt"))
        n.setSection("zentao.tasks", accountId: "zt"); n.setScope("6", accountId: "zt")
        n.setSection("zentao.bugs", accountId: "zt")
        XCTAssertNil(n.location(for: "zt").scopeId, "a section opened for the first time has no scope yet")
        n.setScope("1", accountId: "zt")
        n.setSection("zentao.tasks", accountId: "zt")
        XCTAssertEqual(n.location(for: "zt").scopeId, "6")
        n.setSection("zentao.bugs", accountId: "zt")
        XCTAssertEqual(n.location(for: "zt").scopeId, "1")
        n.setSection("zentao.bugs", accountId: "zt")
        XCTAssertEqual(n.location(for: "zt").scopeId, "1", "the section on screen stays as it is")
    }

    // MARK: what a place kept alive behind another one reads

    func testTheToolAccountStaysWhileTheRailIsElsewhere() {
        let n = nav()
        XCTAssertNil(n.toolAccountId)
        n.select(.account("a"))
        XCTAssertEqual(n.toolAccountId, "a")
        n.select(.chat); XCTAssertEqual(n.toolAccountId, "a", "its boards stay as they are behind the chat")
        n.select(.settings); XCTAssertEqual(n.toolAccountId, "a")
        n.select(.account("b")); XCTAssertEqual(n.toolAccountId, "b")
        n.select(.chat)
        n.onAccountRemoved("b"); XCTAssertNil(n.toolAccountId)
        n.select(.account("a")); n.select(.chat)
        n.onWorkspaceSwitched(newAccounts: []); XCTAssertNil(n.toolAccountId, "no account of the workspace left")
    }

    func testEachSectionKeepsItsOwnScopeBehindTheOther() {
        let n = nav()
        n.select(.account("zt"))
        n.setSection("zentao.tasks", accountId: "zt"); n.setScope("exec7", accountId: "zt")
        n.setSection("zentao.bugs", accountId: "zt"); n.setScope("prod3", accountId: "zt")
        XCTAssertEqual(n.scope(of: "zentao.bugs", accountId: "zt"), "prod3")
        XCTAssertEqual(n.scope(of: "zentao.tasks", accountId: "zt"), "exec7", "not the scope of the section on screen")
        n.setSection("zentao.tasks", accountId: "zt")
        XCTAssertEqual(n.scope(of: "zentao.tasks", accountId: "zt"), "exec7")
        XCTAssertEqual(n.scope(of: "zentao.bugs", accountId: "zt"), "prod3")
        n.setScope("exec9", accountId: "zt")
        XCTAssertEqual(n.scope(of: "zentao.tasks", accountId: "zt"), "exec9")
        XCTAssertEqual(n.location(for: "zt").scope(of: "zentao.bugs"), "prod3")
    }

    /// Whether reading `read` is told about a change made by `change`.
    private func isTold(_ n: AppNavController, of change: () -> Void, reading read: @escaping () -> Void) -> Bool {
        let told = Flag()
        withObservationTracking(read) { told.on = true }
        change()
        return told.on
    }

    func testAKeptPlaceIsNotToldAboutATripToAnotherPlace() {
        let n = nav()
        n.select(.account("zt"))
        n.setSection("zentao.tasks", accountId: "zt"); n.setScope("exec7", accountId: "zt")
        n.openTicket("t1")
        let board = { _ = n.toolAccountId; _ = n.scope(of: "zentao.tasks", accountId: "zt"); _ = n.toolOpenTicketId }

        XCTAssertFalse(isTold(n, of: { n.select(.chat) }, reading: board))
        XCTAssertFalse(isTold(n, of: { n.select(.account("zt")) }, reading: board))
        XCTAssertFalse(isTold(n, of: { n.setSection("zentao.bugs", accountId: "zt") }, reading: board),
                       "the other section on screen: the Tasks board keeps its scope")
        XCTAssertEqual(n.toolOpenTicketId, "t1")
        XCTAssertFalse(isTold(n, of: { n.setScope("prod3", accountId: "zt") }, reading: board))
        // What it does show changed.
        XCTAssertTrue(isTold(n, of: { n.setSection("zentao.tasks", accountId: "zt"); n.setScope("exec9", accountId: "zt") }, reading: board))
        XCTAssertTrue(isTold(n, of: { n.openTicket("t2") }, reading: board))
        XCTAssertTrue(isTold(n, of: { n.select(.account("other")) }, reading: board))
        // The whole state still follows everything.
        XCTAssertTrue(isTold(n, of: { n.select(.chat) }, reading: { _ = n.state }))
        XCTAssertTrue(isTold(n, of: { n.select(.settings) }, reading: { _ = n.rail }))
    }

    func testEachPartOfTheStateIsReadOnItsOwn() {
        let n = nav()
        n.select(.account("zt"))
        let rail = { _ = n.rail }, covers = { _ = n.editor; _ = n.miniAppId }
        let sections = { _ = n.workspaceSection; _ = n.settingsSection }
        // The rail and what covers a place are not told about a ticket, a section of the account or a Settings page.
        XCTAssertFalse(isTold(n, of: { n.openTicket("t1") }, reading: rail))
        XCTAssertFalse(isTold(n, of: { n.openTicket("t2") }, reading: covers))
        XCTAssertFalse(isTold(n, of: { n.setSection("zentao.bugs", accountId: "zt") }, reading: rail))
        XCTAssertFalse(isTold(n, of: { n.setSettingsSection("about") }, reading: rail))
        XCTAssertFalse(isTold(n, of: { n.openTicket("t3") }, reading: sections))
        XCTAssertFalse(isTold(n, of: { n.openEditor(.newBug(accountId: "zt")) }, reading: { _ = n.ticketHistories; _ = n.locations }))
        // Each is told about its own.
        XCTAssertTrue(isTold(n, of: { n.openEditor(.newTask(accountId: "zt")) }, reading: covers))
        XCTAssertTrue(isTold(n, of: { n.openMiniApp("m") }, reading: covers))
        XCTAssertTrue(isTold(n, of: { n.setSettingsSection("general") }, reading: sections))
        XCTAssertTrue(isTold(n, of: { n.setWorkspaceSection("members") }, reading: sections))
        XCTAssertTrue(isTold(n, of: { n.select(.chat) }, reading: rail))
        XCTAssertTrue(isTold(n, of: { n.openTicket("t4") }, reading: { _ = n.state }), "the whole state follows every change")
    }

    func testAPlaceMarksItsOwnOpenTicket() {
        let n = nav()
        n.select(.account("a")); n.openTicket("1")
        n.select(.workspace); n.openTicket("w")
        XCTAssertEqual(n.openTicketId, "w")
        XCTAssertEqual(n.openTicketId(at: .account("a")), "1")
        XCTAssertEqual(n.toolOpenTicketId, "1", "the board behind the dashboard still marks its ticket")
        XCTAssertEqual(n.openTicketId(at: .workspace), "w")
    }
}

private final class Flag: @unchecked Sendable { var on = false }
