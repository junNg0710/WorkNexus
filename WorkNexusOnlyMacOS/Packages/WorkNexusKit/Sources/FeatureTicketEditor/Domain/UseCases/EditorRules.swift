import CoreDomain
import Foundation

/// Ported from: lib/features/ticket_editor/presentation/providers/{bug,task}_editor_controller.dart (the pure rules)
/// What changing a form's product / project / execution does to the draft and its choices - kept out of the
/// controllers so it is testable without a UI.
public enum EditorRules {
    /// `draft` moved to a new product / project / execution: the dependent picks start over (the module only when
    /// the product changed).
    public static func bugScope(_ draft: BugDraft, product: String?, project: String?, execution: String?) -> BugDraft {
        var d = draft
        d.product = product ?? draft.product
        d.project = project ?? draft.project
        d.execution = execution ?? draft.execution
        d.module = product == nil ? draft.module : "0"
        d.story = "0"
        d.task = "0"
        return d
    }

    /// `fetched` choices for a changed scope. A product's choices hold the same lists of products and users, so an
    /// empty list there keeps the form's current one.
    public static func mergeBugOptions(current: BugFormOptions, fetched: BugFormOptions) -> BugFormOptions {
        var o = fetched
        if o.products.isEmpty { o.products = current.products }
        if o.users.isEmpty { o.users = current.users }
        return o
    }

    /// The affected builds the new choices still offer (`trunk` always).
    public static func prunedBuilds(_ draft: BugDraft, options: BugFormOptions) -> [String] {
        let known = Set(options.builds.map(\.value)).union(["trunk"])
        return draft.openedBuilds.filter(known.contains)
    }

    /// A task moved to `execution`: its module and story start over.
    public static func taskExecution(_ draft: TaskDraft, execution: String) -> TaskDraft {
        var d = draft
        d.execution = execution
        d.module = "0"
        d.story = "0"
        return d
    }

    /// `fetched` task choices; an empty execution list keeps the form's current one.
    public static func mergeTaskOptions(current: TaskFormOptions, fetched: TaskFormOptions) -> TaskFormOptions {
        var o = fetched
        if o.executions.isEmpty { o.executions = current.executions }
        return o
    }

    /// Whether the draft differs from the form as loaded (nothing written yet means nothing to keep).
    public static func isWritten<D: Equatable>(_ draft: D, loaded: D, alreadyKept: Bool) -> Bool { alreadyKept || draft != loaded }

    /// A draft as kept: added files are left out (only their bytes exist).
    public static func keptBug(id: String, accountId: String, uid: String, now: Date, draft: BugDraft) -> ZenTaoSavedDraft {
        var d = draft; d.newFiles = []
        return ZenTaoSavedDraft(id: id, accountId: accountId, uid: uid, updatedAt: now, content: .bug(d))
    }
    public static func keptTask(id: String, accountId: String, uid: String, now: Date, draft: TaskDraft) -> ZenTaoSavedDraft {
        var d = draft; d.newFiles = []
        return ZenTaoSavedDraft(id: id, accountId: accountId, uid: uid, updatedAt: now, content: .task(d))
    }
}
