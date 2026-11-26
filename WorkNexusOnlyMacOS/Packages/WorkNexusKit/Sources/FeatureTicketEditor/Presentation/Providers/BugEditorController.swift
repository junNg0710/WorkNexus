import CoreDomain
import CoreTools
import CoreUI
import Foundation
import Observation

/// Ported from: lib/features/ticket_editor/presentation/providers/bug_editor_controller.dart
/// Loads, edits and saves the bug the editor is open on (`.newBug` or `.editBug`). A new bug is kept as a draft
/// while it is written, and reopens from it (`draftId`).
@MainActor @Observable
public final class BugEditorController {
    public private(set) var state: BugEditorState?
    public private(set) var loadFailure: Failure?
    public private(set) var isLoading = true
    /// The steps' rich text, made once the bug has loaded (read back into the draft as it changes and on save).
    @ObservationIgnored public private(set) var steps: HtmlEditingController?

    public let launch: TicketEditorLaunch
    private let gateway: TicketEditorGateway
    private let autosave: DraftAutosave?
    private let now: () -> Date
    @ObservationIgnored private var sync: RichTextDraftSync?

    /// What a new ticket starts filled in with (one made from a chat message); nil for an ordinary one.
    private let prefill: TicketEditorPrefill?

    public init(launch: TicketEditorLaunch, gateway: TicketEditorGateway, autosaveDelay: Duration = DraftAutosave.defaultDelay,
                prefill: TicketEditorPrefill? = nil, now: @escaping () -> Date = Date.init) {
        self.launch = launch; self.gateway = gateway; self.now = now; self.prefill = prefill
        autosave = gateway.drafts.map { DraftAutosave($0, delay: autosaveDelay) }
    }

    // MARK: Loading

    public func load() async {
        isLoading = true; loadFailure = nil
        guard case .success(let editor) = gateway.requireEditor() else { return fail(TicketEditorGateway.unavailable) }
        let accountId = launch.accountId
        if case .newBug(_, _, _, _, _, let draftId?) = launch, let drafts = gateway.drafts {
            switch await drafts.read(id: draftId) {
            case .failure(let f): return fail(f)
            case .success(let kept):
                if let kept, case .bug = kept.content { return await restore(kept, editor) }
            }
        }
        let res: Outcome<BugForm>
        switch launch {
        case .newBug(_, let product, let copyOf, let execution, let task, _):
            res = await editor.newBugForm(accountId: accountId, productId: product, copyOf: copyOf, executionId: execution, taskId: task)
        case .editBug(_, let bugId): res = await editor.editBugForm(accountId: accountId, bugId: bugId)
        default: return fail(.unexpected("Not a bug launch: \(launch)"))
        }
        switch res {
        case .failure(let f): fail(f)
        case .success(let form):
            let uid = FormValueFormat.newFormUid()
            var draft = form.draft
            // A new bug made from a chat message: ZenTao's form (product, defaults) with the message as title, and quoted
            // above the form's own steps template (steps / result / expected), which stays to be filled in.
            if launch.isNew, let prefill {
                let body = await PlacePrefillPictures()(prefill) { await editor.uploadImage(accountId: accountId, uid: uid, bytes: $0, fileName: $1).value }
                draft.title = prefill.title; draft.steps = body + draft.steps
            }
            begin(BugEditorState(form: form, draft: draft, uid: uid, draftId: launch.isNew ? (launch.draftId ?? uid) : nil))
            // Already written, by the messages it quotes: kept from the start.
            if launch.isNew, prefill != nil { keepDraft() }
        }
    }

    /// The form of `kept`'s product (with the choices of its project and execution), filled in as the draft was left.
    private func restore(_ kept: ZenTaoSavedDraft, _ editor: ZenTaoTicketEditor) async {
        guard case .bug(let draft) = kept.content else { return }
        switch await editor.newBugForm(accountId: launch.accountId, productId: draft.product, copyOf: nil, executionId: nil, taskId: nil) {
        case .failure(let f): fail(f)
        case .success(var form):
            if draft.project != "0" || draft.execution != "0", let options = await fetchOptions(form.options, draft) { form.options = options }
            begin(BugEditorState(form: form, draft: draft, uid: kept.uid, draftId: kept.id, draftSavedAt: kept.updatedAt))
        }
    }

    private func fail(_ f: Failure) { loadFailure = f; isLoading = false }

    private func begin(_ s: BugEditorState) {
        state = s; isLoading = false
        let text = HtmlEditingController(html: s.draft.steps)
        steps = text
        sync = RichTextDraftSync(text) { [weak self] html in
            guard let self, self.state?.draft.steps != html else { return }
            self.edit { $0.steps = html }
        }
    }

    /// `draft`'s product / project / execution choices; nil when ZenTao did not give them.
    private func fetchOptions(_ current: BugFormOptions, _ draft: BugDraft) async -> BugFormOptions? {
        guard case .success(let editor) = gateway.requireEditor() else { return nil }
        let res = await editor.bugOptions(accountId: launch.accountId, productId: draft.product, projectId: draft.project, executionId: draft.execution)
        guard case .success(let fetched) = res else { return nil }
        return EditorRules.mergeBugOptions(current: current, fetched: fetched)
    }

    // MARK: Editing

    /// Hands the steps' text to the draft now (before saving or closing).
    public func pushRichText() { sync?.pushNow() }

    public func edit(_ change: (inout BugDraft) -> Void) {
        guard var s = state else { return }
        change(&s.draft)
        s.missing = []
        state = s
        keepDraft()
    }

    /// Sets the product / project / execution, and reloads the choices that depend on them (modules, builds,
    /// stories...), dropping picks they no longer offer.
    public func changeScope(product: String? = nil, project: String? = nil, execution: String? = nil) async {
        guard var s = state else { return }
        s.draft = EditorRules.bugScope(s.draft, product: product, project: project, execution: execution)
        state = s
        keepDraft()
        guard let options = await fetchOptions(s.form.options, s.draft), var now = state else { return }
        now.form.options = options
        now.draft.openedBuilds = EditorRules.prunedBuilds(now.draft, options: options)
        state = now
    }

    public var imageLoader: ImageBytesLoader? {
        guard let editor = gateway.editor else { return nil }
        let account = launch.accountId
        return { url in await editor.loadImage(accountId: account, url: url) }
    }

    /// Uploads an image put into the steps; the URL to embed it at, or nil.
    public func uploadImage(_ bytes: Data, _ name: String) async -> String? {
        guard let s = state, case .success(let editor) = gateway.requireEditor() else { return nil }
        return await editor.uploadImage(accountId: launch.accountId, uid: s.uid, bytes: bytes, fileName: name).value
    }

    // MARK: Drafts

    /// Keeps the draft once typing pauses - once something was written.
    private func keepDraft() {
        guard let s = state, let id = s.draftId, let autosave else { return }
        guard EditorRules.isWritten(s.draft, loaded: s.form.draft, alreadyKept: s.draftSavedAt != nil) else { return autosave.cancel() }
        autosave.schedule(EditorRules.keptBug(id: id, accountId: launch.accountId, uid: s.uid, now: now(), draft: s.draft)) { [weak self] kept in
            guard let self, var now = self.state else { return }
            switch kept {
            case .success(let at): now.draftSavedAt = at
            case .failure(let f): now.failure = f
            }
            self.state = now
        }
    }

    /// Deletes the kept draft; later changes are not kept. False (with the state's `failure` set) when it could not
    /// be deleted, and the editor stays open.
    public func discardDraft() async -> Bool {
        guard var s = state, let id = s.draftId, let autosave else { return true }
        let res = await autosave.discard(id)
        s = state ?? s
        switch res {
        case .success: s.draftId = nil; s.draftSavedAt = nil; state = s; return true
        case .failure(let f): s.failure = f; state = s; return false
        }
    }

    /// Leaving the editor keeps the last change; stops the text sync.
    public func close() async {
        pushRichText()
        sync?.stop()
        await autosave?.flush()
    }

    // MARK: Saving

    /// Saves the bug; the saved bug's ticket id, or nil when it was not saved (a field missing, or ZenTao refused it -
    /// see the state's `failure`).
    public func save() async -> String? {
        pushRichText()
        guard let s = state, !s.saving else { return nil }
        let missing = ValidateBugDraft()(s.draft)
        guard missing.isEmpty else { state?.missing = missing; return nil }
        guard case .success(let editor) = gateway.requireEditor() else { state?.failure = TicketEditorGateway.unavailable; return nil }
        state?.saving = true; state?.failure = nil
        let res = await editor.saveBug(accountId: launch.accountId, form: s.form, draft: s.draft, uid: s.uid)
        switch res {
        case .success(let ticketId):
            // In ZenTao now: nothing left to keep, and no later change kept again.
            let id = state?.draftId
            state?.saving = false; state?.draftId = nil
            if let id { _ = await autosave?.discard(id) }
            return ticketId
        case .failure(let f):
            state?.saving = false; state?.failure = f
            return nil
        }
    }
}
