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
}
