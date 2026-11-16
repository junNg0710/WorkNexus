import CoreDomain
import CoreTools
import CoreUI
import Foundation
import Observation

/// Ported from: lib/features/ticket_editor/presentation/providers/task_editor_controller.dart
/// Loads, edits and saves the task the editor is open on (`.newTask` or `.editTask`). A new task is kept as a draft
/// while it is written, and reopens from it (`draftId`). A new task with `parentId` is a subtask: saving it posts
/// ZenTao's batch task form (the editor service does that when `draft.parent != "0"`).
@MainActor @Observable
public final class TaskEditorController {
    public private(set) var state: TaskEditorState?
    public private(set) var loadFailure: Failure?
    public private(set) var isLoading = true
    /// The description's rich text, made once the task has loaded.
    @ObservationIgnored public private(set) var desc: HtmlEditingController?

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
        if case .newTask(_, _, _, let draftId?, _) = launch, let drafts = gateway.drafts {
            switch await drafts.read(id: draftId) {
            case .failure(let f): return fail(f)
            case .success(let kept):
                if let kept, case .task(let draft) = kept.content { return await restore(kept, draft, editor) }
            }
        }
        let res: Outcome<TaskForm>
        switch launch {
        case .newTask(_, let execution, let parent, _, let copyOf):
            res = await editor.newTaskForm(accountId: accountId, executionId: execution, parentId: parent, copyOf: copyOf)
        case .editTask(_, let taskId): res = await editor.editTaskForm(accountId: accountId, taskId: taskId)
        default: return fail(.unexpected("Not a task launch: \(launch)"))
        }
        switch res {
        case .failure(let f): fail(f)
        case .success(let form):
            let uid = FormValueFormat.newFormUid()
            var draft = form.draft
            if launch.isNew, let prefill { draft.name = prefill.title; draft.desc = prefill.bodyHtml + draft.desc }
            begin(TaskEditorState(form: form, draft: draft, uid: uid, draftId: launch.isNew ? (launch.draftId ?? uid) : nil))
        }
    }

    /// The form of `kept`'s execution (and parent), filled in as the draft was left.
    private func restore(_ kept: ZenTaoSavedDraft, _ draft: TaskDraft, _ editor: ZenTaoTicketEditor) async {
        switch await editor.newTaskForm(accountId: launch.accountId, executionId: draft.execution,
                                        parentId: draft.parent == "0" ? nil : draft.parent, copyOf: nil) {
        case .failure(let f): fail(f)
        case .success(let form):
            begin(TaskEditorState(form: form, draft: draft, uid: kept.uid, draftId: kept.id, draftSavedAt: kept.updatedAt))
        }
    }

    private func fail(_ f: Failure) { loadFailure = f; isLoading = false }

    private func begin(_ s: TaskEditorState) {
        state = s; isLoading = false
        let text = HtmlEditingController(html: s.draft.desc)
        desc = text
        sync = RichTextDraftSync(text) { [weak self] html in
            guard let self, self.state?.draft.desc != html else { return }
            self.edit { $0.desc = html }
        }
    }

    // MARK: Editing

    public func pushRichText() { sync?.pushNow() }

    public func edit(_ change: (inout TaskDraft) -> Void) {
        guard var s = state else { return }
        change(&s.draft)
        s.missing = []
        state = s
        keepDraft()
    }

    /// Moves the task to `execution` and reloads its modules, stories and members.
    public func changeExecution(_ execution: String) async {
        guard var s = state else { return }
        s.draft = EditorRules.taskExecution(s.draft, execution: execution)
        state = s
        keepDraft()
        guard case .success(let editor) = gateway.requireEditor() else { return }
        guard case .success(let fetched) = await editor.taskOptions(accountId: launch.accountId, executionId: execution),
              var now = state else { return }
        var options = EditorRules.mergeTaskOptions(current: now.form.options, fetched: fetched)
        // The form gave no assignees: the execution's team members are who it can go to.
        if options.users.isEmpty, let members = gateway.members,
           case .success(let team) = await members.executionMembers(accountId: launch.accountId, executionId: execution) {
            options.users = team.map { FormOption(value: $0.account, label: $0.displayName) }
        }
        now.form.options = options
        state = now
    }

    public var imageLoader: ImageBytesLoader? {
        guard let editor = gateway.editor else { return nil }
        let account = launch.accountId
        return { url in await editor.loadImage(accountId: account, url: url) }
    }

    public func uploadImage(_ bytes: Data, _ name: String) async -> String? {
        guard let s = state, case .success(let editor) = gateway.requireEditor() else { return nil }
        return await editor.uploadImage(accountId: launch.accountId, uid: s.uid, bytes: bytes, fileName: name).value
    }

    // MARK: Drafts

    private func keepDraft() {
        guard let s = state, let id = s.draftId, let autosave else { return }
        guard EditorRules.isWritten(s.draft, loaded: s.form.draft, alreadyKept: s.draftSavedAt != nil) else { return autosave.cancel() }
        autosave.schedule(EditorRules.keptTask(id: id, accountId: launch.accountId, uid: s.uid, now: now(), draft: s.draft)) { [weak self] kept in
            guard let self, var now = self.state else { return }
            switch kept {
            case .success(let at): now.draftSavedAt = at
            case .failure(let f): now.failure = f
            }
            self.state = now
        }
    }

    public func discardDraft() async -> Bool {
        guard var s = state, let id = s.draftId, let autosave else { return true }
        let res = await autosave.discard(id)
        s = state ?? s
        switch res {
        case .success: s.draftId = nil; s.draftSavedAt = nil; state = s; return true
        case .failure(let f): s.failure = f; state = s; return false
        }
    }

    public func close() async {
        pushRichText()
        sync?.stop()
        await autosave?.flush()
    }

    // MARK: Saving

    /// Saves the task; its ticket id, or nil when it was not saved.
    public func save() async -> String? {
        pushRichText()
        guard let s = state, !s.saving else { return nil }
        let missing = ValidateTaskDraft()(s.draft)
        guard missing.isEmpty else { state?.missing = missing; return nil }
        guard case .success(let editor) = gateway.requireEditor() else { state?.failure = TicketEditorGateway.unavailable; return nil }
        state?.saving = true; state?.failure = nil
        let res = await editor.saveTask(accountId: launch.accountId, form: s.form, draft: s.draft, uid: s.uid)
        switch res {
        case .success(let ticketId):
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
