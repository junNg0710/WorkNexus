import CoreDomain
import CoreUI
import Foundation

/// Ported from: lib/tools/gitlab/presentation/providers/gitlab_detail_providers.dart + the `_run` helpers of
/// gitlab_mr_detail.dart / gitlab_ticket_actions.dart. Runs a merge-request state command through its use case and
/// words the toast.
enum GitlabMrAction: Equatable {
    case approve, unapprove, rebase, close, reopen
    case merge(squash: Bool, removeSourceBranch: Bool)
    case setDraft(Bool)

    /// What a button spinner / disabled state keys on.
    enum Kind: Hashable { case approve, unapprove, rebase, close, reopen, merge, draft }

    var kind: Kind {
        switch self {
        case .approve: .approve; case .unapprove: .unapprove; case .rebase: .rebase; case .close: .close
        case .reopen: .reopen; case .merge: .merge; case .setDraft: .draft
        }
    }
}

struct GitlabActionRunner {
    let service: GitLabMrService

    func perform(_ action: GitlabMrAction, _ ticket: Ticket) async -> Outcome<Void> {
        switch action {
        case .approve: await ApproveGitLabMr(service)(ticket)
        case .unapprove: await UnapproveGitLabMr(service)(ticket)
        case .rebase: await RebaseGitLabMr(service)(ticket)
        case .close: await CloseGitLabMr(service)(ticket)
        case .reopen: await ReopenGitLabMr(service)(ticket)
        case .merge(let squash, let remove): await MergeGitLabMr(service)(ticket, squash: squash, removeSourceBranch: remove)
        case .setDraft(let draft): await SetGitLabMrDraft(service)(ticket, draft: draft)
        }
    }

    func successMessage(_ action: GitlabMrAction, _ ticket: Ticket) -> String {
        let key = ticket.externalKey
        switch action {
        case .approve: return appFormat("gitlabMrApproved", "Approved !%1$@", key)
        case .unapprove: return appFormat("gitlabMrUnapproved", "Revoked approval on !%1$@", key)
        case .merge: return appFormat("gitlabMrMerged", "Merged !%1$@", key)
        case .rebase: return appFormat("gitlabMrRebased", "Rebased !%1$@", key)
        case .close: return appFormat("gitlabMrClosed", "Closed merge request !%1$@", key)
        case .reopen: return appFormat("gitlabMrReopened", "Reopened merge request !%1$@", key)
        case .setDraft(let draft):
            return draft ? appFormat("gitlabMrMarkedDraft", "Marked !%1$@ as draft", key) : appFormat("gitlabMrMarkedReady", "Marked !%1$@ as ready", key)
        }
    }

    static func failureMessage(_ f: Failure, fallback: String? = nil) -> String {
        appFormat("actionFailed", "Failed: %1$@", f.message.isEmpty ? (fallback ?? appString("providerActionFailed", "Provider action failed")) : f.message)
    }
}

/// The state actions of a merge request that ask for confirmation first (merge, rebase and close change the branch or
/// the request itself and cannot simply be taken back from the app).
enum GitlabMrConfirm: Identifiable, Equatable {
    case merge(squash: Bool, removeSourceBranch: Bool), rebase, close

    var id: String { switch self { case .merge: "merge"; case .rebase: "rebase"; case .close: "close" } }
    var destructive: Bool { self == .close }

    var action: GitlabMrAction {
        switch self {
        case .merge(let s, let r): .merge(squash: s, removeSourceBranch: r)
        case .rebase: .rebase
        case .close: .close
        }
    }

    func title(_ key: String) -> String {
        switch self {
        case .merge: appFormat("gitlabConfirmMergeTitle", "Merge !%1$@?", key)
        case .rebase: appFormat("gitlabConfirmRebaseTitle", "Rebase !%1$@?", key)
        case .close: appFormat("gitlabConfirmCloseTitle", "Close !%1$@?", key)
        }
    }

    func message(source: String?, target: String?) -> String {
        switch self {
        case .merge(let squash, let remove):
            var text = appFormat("gitlabConfirmMergeBody", "This merges %1$@ into %2$@ and cannot be undone from here.",
                                 source ?? "the source branch", target ?? "the target branch")
            if squash { text += " " + appString("gitlabConfirmSquash", "The commits are squashed.") }
            if remove { text += " " + appString("gitlabConfirmRemoveBranch", "The source branch is deleted.") }
            return text
        case .rebase: return appString("gitlabConfirmRebaseBody", "The source branch is rebased onto the target branch. Its commits get new hashes.")
        case .close: return appString("gitlabConfirmCloseBody", "The merge request will be closed without merging. You can reopen it later.")
        }
    }

    var confirmLabel: String {
        switch self {
        case .merge: appString("gitlabMerge", "Merge")
        case .rebase: appString("rebase", "Rebase")
        case .close: appString("close", "Close")
        }
    }
}
