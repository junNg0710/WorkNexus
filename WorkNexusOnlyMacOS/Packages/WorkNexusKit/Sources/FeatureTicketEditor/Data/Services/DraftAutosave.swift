import CoreDomain
import Foundation

/// Ported from: lib/features/ticket_editor/presentation/providers/ticket_draft_providers.dart (`DraftAutosave`)
/// Keeps a new ticket's draft while it is written: a change is kept once typing pauses (a `Task` sleeps `delay`),
/// and a change still waiting when the editor closes is kept then (`flush`).
@MainActor
public final class DraftAutosave {
    public static let defaultDelay: Duration = .milliseconds(800)

    private let repository: ZenTaoTicketDraftRepository
    private let delay: Duration
    private var timer: Task<Void, Never>?
    /// The latest change, waiting to be kept - a value, so the last one is kept even after the editor is gone.
    private var pending: ZenTaoSavedDraft?
    private var onKept: (@MainActor (Outcome<Date>) -> Void)?

    public init(_ repository: ZenTaoTicketDraftRepository, delay: Duration = DraftAutosave.defaultDelay) {
        self.repository = repository
        self.delay = delay
    }

    /// Keeps `draft` once `delay` passes without another change; `onKept` is told when it was kept, or why not.
    public func schedule(_ draft: ZenTaoSavedDraft, onKept: (@MainActor (Outcome<Date>) -> Void)? = nil) {
        pending = draft
        self.onKept = onKept
        timer?.cancel()
        timer = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.keepPending()
        }
    }

    /// Keeps the waiting change now, if there is one.
    public func flush() async {
        timer?.cancel()
        timer = nil
        await keepPending()
    }

    /// Writes the waiting change in a task of its own: the database refuses a write from a cancelled task, and the
    /// caller is one whenever the next change restarts the timer or the editor's view goes away while this runs. A
    /// change that could not be kept waits for the next try (the next change, or the editor closing).
    private func keepPending() async {
        guard let draft = pending else { return }
        let callback = onKept
        pending = nil
        let repository = repository
        let res = await Task { await repository.save(draft) }.value
        if case .failure = res, pending == nil { pending = draft; onKept = callback }
        callback?(res.map { _ in draft.updatedAt })
    }

    /// Drops the waiting change (the ticket was saved or the draft discarded).
    public func cancel() {
        timer?.cancel()
        timer = nil
        pending = nil
    }

    /// Cancels any waiting change and deletes draft `id`.
    public func discard(_ id: String) async -> Outcome<Void> {
        cancel()
        return await repository.delete(id: id)
    }
}
