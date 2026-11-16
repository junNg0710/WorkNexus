import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/tools/github/presentation/detail/github_pr_detail.dart
/// Wires the GitHub PR two-pane `GithubPrOverview` to the PR service. Every state action asks for confirmation, then
/// goes through the optimistic service path and reports a toast; assign / reviewers go straight to the service.
struct GithubPrDetail: View {
    @Environment(\.toasts) private var toasts
    let ctx: GithubContext
    let ticket: Ticket
    let entity: GitHubItemEntity
    let onClose: () -> Void
    @State private var model: GithubPrDetailModel
    @State private var busy = false
    @State private var pending: GithubPrConfirm?

    init(ctx: GithubContext, ticket: Ticket, entity: GitHubItemEntity, onClose: @escaping () -> Void) {
        self.ctx = ctx; self.ticket = ticket; self.entity = entity; self.onClose = onClose
        _model = State(initialValue: GithubPrDetailModel(ticketId: ticket.id, services: ctx.services))
    }

    var body: some View {
        let commands = GithubPrCommands(merge: { pending = .merge }, updateBranch: { pending = .updateBranch },
                                        close: { pending = .close }, reopen: { run(.reopen) })
        GithubPrOverview(ctx: ctx, ticket: ticket, entity: entity, isSyncing: model.syncing, comments: model.comments,
                         activity: model.activity, busy: busy, commands: commands, onClose: onClose,
                         onSync: { model.refresh(ticket) }, onComment: postComment)
            .task(id: ticket.id) { await model.run() }
            .appDialog(item: $pending) { action in
                AppConfirmDialog(title: action.title(ticket.externalKey), message: action.message(head: entity.headBranch, base: entity.baseBranch),
                                 confirmLabel: action.confirmLabel, destructive: action.destructive,
                                 onConfirm: { pending = nil; run(action.command) },
                                 onCancel: { pending = nil })
            }
    }

    private func postComment(_ body: String) async -> Bool {
        let res = await PostGitHubComment(ctx.prService)(ticket, body: body)
        if case .failure(let f) = res {
            toasts?.show(GithubActionRunner.failureMessage(f, fallback: appString("commentPostFailed", "Couldn't post comment")), kind: .error)
            return false
        }
        return true
    }

    private func run(_ command: GithubPrCommand) {
        guard !busy else { return }
        busy = true
        let t = ticket, runner = GithubActionRunner(service: ctx.prService)
        Task {
            let res = await runner.perform(command, t)
            busy = false
            switch res {
            case .success: toasts?.show(runner.successMessage(command, t))
            case .failure(let f): toasts?.show(GithubActionRunner.failureMessage(f), kind: .error)
            }
        }
    }
}

/// The state-changing commands the panels trigger (merge / update branch / close ask first; reopen runs at once).
struct GithubPrCommands {
    var merge: () -> Void
    var updateBranch: () -> Void
    var close: () -> Void
    var reopen: () -> Void
}
