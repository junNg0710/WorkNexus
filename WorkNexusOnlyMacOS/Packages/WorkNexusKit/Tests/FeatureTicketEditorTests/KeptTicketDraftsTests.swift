/// Not in the Flutter app: the kept drafts as the rail's "+" menu offers them.
import CoreDomain
import CoreTools
import XCTest
@testable import FeatureTicketEditor

@MainActor
final class KeptTicketDraftsTests: XCTestCase {
    private func bug(_ id: String, account: String = "a", at: Double, product: String = "7") -> ZenTaoSavedDraft {
        ZenTaoSavedDraft(id: id, accountId: account, uid: "u-\(id)", updatedAt: Date(timeIntervalSince1970: at), content: .bug(BugDraft(product: product)))
    }

    private func task(_ id: String, account: String = "a", at: Double, execution: String = "5") -> ZenTaoSavedDraft {
        ZenTaoSavedDraft(id: id, accountId: account, uid: "u-\(id)", updatedAt: Date(timeIntervalSince1970: at), content: .task(TaskDraft(execution: execution)))
    }

    /// The drafts of the workspace's accounts, the one last written first, no more than the menu takes.
    func testTheMenuOffersTheNewestDraftsOfItsAccounts() async {
        let kept = KeptTicketDrafts()
        await kept.run(FakeDrafts([bug("b1", at: 10), task("t1", at: 30), bug("other", account: "z", at: 40), task("t2", at: 20)]))
        XCTAssertEqual(kept.offered(accounts: ["a"]).map(\.id), ["t1", "t2", "b1"])
        XCTAssertEqual(kept.offered(accounts: ["a"], limit: 2).map(\.id), ["t1", "t2"])
        XCTAssertEqual(kept.offered(accounts: ["a", "z"]).first?.id, "other")
        XCTAssertTrue(kept.offered(accounts: []).isEmpty)
    }

    /// A board's "New bug" / "New task" button lists the drafts of its own kind and account; discarding takes them away.
    func testABoardsButtonListsItsOwnDraftsAndDiscardsThem() async {
        let stored = FakeDrafts([bug("b1", at: 10), task("t1", at: 30), task("other", account: "z", at: 40), task("t2", at: 50)])
        let kept = KeptTicketDrafts()
        await kept.run(stored)
        XCTAssertEqual(kept.drafts(accountId: "a", isBug: false).map(\.id), ["t2", "t1"])
        XCTAssertEqual(kept.drafts(accountId: "a", isBug: true).map(\.id), ["b1"])
        let failure = await KeptTicketDrafts.discard(kept.drafts(accountId: "a", isBug: false), from: stored)
        XCTAssertNil(failure)
        XCTAssertEqual(Set(stored.all.map(\.id)), ["b1", "other"])
        // One that cannot be deleted says why.
        stored.deleteFailure = .storage("locked")
        let refused = await KeptTicketDrafts.discard(stored.all, from: stored)
        XCTAssertEqual(refused?.message, "locked")
    }

    /// Picking a draft opens the editor on it, in the product or execution it was written for.
    func testADraftsRouteOpensTheEditorOnIt() {
        let b = bug("b1", at: 1, product: "9"), t = task("t1", at: 1, execution: "31")
        XCTAssertEqual(KeptTicketDrafts.route(b), .newBug(accountId: "a", productId: "9", draftId: "b1"))
        XCTAssertEqual(KeptTicketDrafts.route(t), .newTask(accountId: "a", executionId: "31", draftId: "t1"))
        XCTAssertTrue(KeptTicketDrafts.isBug(b)); XCTAssertFalse(KeptTicketDrafts.isBug(t))
        // The route's draft reaches the editor, which then reads the draft back.
        XCTAssertEqual(TicketEditorView.launch(for: KeptTicketDrafts.route(b)), .resuming(b))
        XCTAssertEqual(TicketEditorView.launch(for: KeptTicketDrafts.route(t)), .resuming(t))
        XCTAssertNil(TicketEditorView.launch(for: .newBug(accountId: "a", productId: "9")).draftId)
    }
}
