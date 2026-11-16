import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/detail/gitlab_mr_detail.dart
/// Wires the GitLab MR two-pane `GitlabMrOverview` to the MR service. Merge, rebase and close ask for confirmation, then
/// every state action goes through its use case (optimistic service path) and reports a toast; assign / reviewers /
/// labels / milestone / time tracking go straight to the service from the sidebar editors.
struct GitlabMrDetail: View {
    @Environment(\.toasts) private var toasts
    let ctx: GitlabContext
    let ticket: Ticket
    let entity: GitLabItemEntity
    let onClose: () -> Void
    @State private var model: GitlabMrDetailModel
    @State private var busy: GitlabMrAction.Kind?
    @State private var pending: GitlabMrConfirm?

    init(ctx: GitlabContext, ticket: Ticket, entity: GitLabItemEntity, onClose: @escaping () -> Void) {
        self.ctx = ctx; self.ticket = ticket; self.entity = entity; self.onClose = onClose
        _model = State(initialValue: GitlabMrDetailModel(ticketId: ticket.id, services: ctx.services))
    }

    private var commands: GitlabMrCommands {
        GitlabMrCommands(busy: busy, approve: { run(.approve) }, unapprove: { run(.unapprove) },
                         merge: { squash, remove in pending = .merge(squash: squash, removeSourceBranch: remove) },
                         rebase: { pending = .rebase }, close: { pending = .close }, reopen: { run(.reopen) },
                         setDraft: { run(.setDraft($0)) })
    }

    var body: some View {
        GitlabMrOverview(ctx: ctx, ticket: ticket, entity: entity, isSyncing: model.syncing, comments: model.comments,
                         activity: model.activity, commands: commands, onClose: onClose,
                         onSync: { model.refresh(ticket) }, onComment: postComment)
            .task(id: ticket.id) { await model.run() }
            .appDialog(item: $pending) { confirm in
                AppConfirmDialog(title: confirm.title(ticket.externalKey), message: confirm.message(source: entity.sourceBranch, target: entity.targetBranch),
                                 confirmLabel: confirm.confirmLabel, destructive: confirm.destructive,
                                 onConfirm: { pending = nil; run(confirm.action) }, onCancel: { pending = nil })
            }
    }

    private func postComment(_ body: String) async -> Bool {
        let res = await PostGitLabMrComment(ctx.mrService)(ticket, body: body)
        if case .failure(let f) = res {
            toasts?.show(GitlabActionRunner.failureMessage(f, fallback: appString("commentPostFailed", "Couldn't post comment")), kind: .error)
            return false
        }
        return true
    }

    private func run(_ action: GitlabMrAction) {
        guard busy == nil else { return }
        busy = action.kind
        let t = ticket, runner = GitlabActionRunner(service: ctx.mrService)
        Task {
            let res = await runner.perform(action, t)
            busy = nil
            switch res {
            case .success: toasts?.show(runner.successMessage(action, t))
            case .failure(let f): toasts?.show(GitlabActionRunner.failureMessage(f), kind: .error)
            }
        }
    }
}
