/// Not in the Flutter app.
import CoreDomain
import Foundation
import Observation

/// The kept drafts of new bugs and tasks, for the places that offer them: the "New bug" / "New task" button of a board,
/// the rail's "+" menu and the editor's "Drafts (n)". Each lists them to go on with, or to discard.
@MainActor @Observable
public final class KeptTicketDrafts {
    /// How many drafts the rail's menu lists; the rest are under a board's own button.
    public static let menuLimit = 8
    public private(set) var all: [ZenTaoSavedDraft] = []

    public init() {}

    /// Follows the stored drafts until the task is cancelled.
    public func run(_ repository: ZenTaoTicketDraftRepository) async {
        for await drafts in repository.watchAll() { all = drafts }
    }

    /// The drafts of `accounts`, the one last written first, at most `limit`.
    public func offered(accounts: Set<String>, limit: Int = KeptTicketDrafts.menuLimit) -> [ZenTaoSavedDraft] {
        Array(all.filter { accounts.contains($0.accountId) }.sorted { $0.updatedAt > $1.updatedAt }.prefix(max(limit, 0)))
    }

    /// The bug (or task) drafts of one account, the one last written first.
    public func drafts(accountId: String, isBug: Bool) -> [ZenTaoSavedDraft] {
        all.filter { $0.accountId == accountId && Self.isBug($0) == isBug }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Whether `draft` is a bug's.
    public nonisolated static func isBug(_ draft: ZenTaoSavedDraft) -> Bool {
        if case .bug = draft.content { true } else { false }
    }

    /// The route that opens the editor on `draft` again, in the product / execution it was written for.
    public nonisolated static func route(_ draft: ZenTaoSavedDraft) -> TicketEditorRoute {
        switch draft.content {
        case .bug(let bug): .newBug(accountId: draft.accountId, productId: bug.product, draftId: draft.id)
        case .task(let task): .newTask(accountId: draft.accountId, executionId: task.execution, draftId: draft.id)
        }
    }

    /// Deletes `gone` for good. The first one that could not be deleted stops it and says why.
    public nonisolated static func discard(_ gone: [ZenTaoSavedDraft], from repository: ZenTaoTicketDraftRepository) async -> Failure? {
        for draft in gone {
            if case .failure(let f) = await repository.delete(id: draft.id) { return f }
        }
        return nil
    }
}
