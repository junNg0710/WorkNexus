import CoreDomain
import XCTest
@testable import FeatureTicketEditor

/// The draft is really written: the timer that fires the write is not what cancels it, and a write that failed is
/// tried again.
@MainActor
final class DraftAutosaveTests: XCTestCase {
    private func draft(_ title: String, at: Double = 1) -> ZenTaoSavedDraft {
        var bug = BugDraft(product: "7"); bug.title = title
        return EditorRules.keptBug(id: "d", accountId: "a", uid: "u", now: Date(timeIntervalSince1970: at), draft: bug)
    }
    private func eventually(_ cond: @autoclosure () -> Bool) async {
        for _ in 0..<150 where !cond() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// The database refuses a write from a cancelled task (the fake does too): the pause timer must not be what the
    /// write runs in once it is cancelled - every draft was lost that way.
    func testTheWriteAfterAPauseIsNotCancelledByItsOwnTimer() async {
        let drafts = FakeDrafts()
        let auto = DraftAutosave(drafts, delay: .milliseconds(10))
        var kept: [Outcome<Date>] = []
        auto.schedule(draft("typed")) { kept.append($0) }
        await eventually(!kept.isEmpty)
        XCTAssertEqual(kept.first?.value, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(drafts.all.first?.title, "typed")
    }

    func testClosingFromACancelledTaskStillKeepsTheLastChange() async {
        let drafts = FakeDrafts()
        let auto = DraftAutosave(drafts, delay: .seconds(60))
        auto.schedule(draft("last words"))
        let closing = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await auto.flush()
        }
        await closing.value
        XCTAssertEqual(drafts.all.first?.title, "last words")
    }

    func testAWriteThatFailedIsTriedAgainWhenTheEditorCloses() async {
        let drafts = FakeDrafts()
        drafts.saveFailures = 1
        let auto = DraftAutosave(drafts, delay: .milliseconds(10))
        var kept: [Outcome<Date>] = []
        auto.schedule(draft("typed")) { kept.append($0) }
        await eventually(!kept.isEmpty)
        XCTAssertNotNil(kept.first?.failure)
        XCTAssertTrue(drafts.all.isEmpty)
        await auto.flush()
        XCTAssertEqual(drafts.all.first?.title, "typed")
        XCTAssertEqual(kept.count, 2)
        // Nothing is written twice once it is kept.
        await auto.flush()
        XCTAssertEqual(drafts.saves, 1)
    }
}
