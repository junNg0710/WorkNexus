import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/detail/gitlab_ticket_actions.dart
/// The action buttons in the detail header: Assign, plus Close / Reopen (issues) or Reviewers / Rebase / Merge / Close /
/// Reopen (MRs), gated on the raw provider status and merge status. Rebase, Merge and Close ask first; actions apply
/// optimistically and report a toast; a merged MR is terminal (no state actions).
struct GitlabActions: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let ctx: GitlabContext
    let ticket: Ticket
    @State private var busy = false
    @State private var dialog: GitlabActionDialog?

    var body: some View {
        let isMr = (ticket.externalType ?? "").lowercased() == "mergerequest"
        let raw = ticket.providerStatus.lowercased()
        let closed = raw == "closed", active = raw != "closed" && raw != "merged"
        let needsRebase = isMr && active && entity?.mergeStatus == "need_rebase"
        return FlowLayout(spacing: theme.spacing.s8, rowSpacing: theme.spacing.s8) {
            button("person.badge.plus", appString("assign", "Assign")) { dialog = .users(multiple: false) }
            if isMr && active { button("square.and.pencil", appString("reviewers", "Reviewers")) { dialog = .users(multiple: true) } }
            if needsRebase { button("arrow.triangle.2.circlepath", appString("rebase", "Rebase")) { dialog = .confirm(.rebase) } }
            if isMr && active { button("arrow.triangle.merge", appString("gitlabMerge", "Merge")) { dialog = .confirm(.merge(squash: false, removeSourceBranch: false)) } }
            if active { button("checkmark.circle", appString("close", "Close")) { dialog = .confirm(.close) } }
            if closed { button("arrow.counterclockwise", appString("gitlabReopen", "Reopen")) { run(.reopen) } }
        }
        .sheet(item: $dialog) { d in
            switch d {
            case .users(let multiple): GitlabAssignDialog(ctx: ctx, ticket: ticket, multiple: multiple) { dialog = nil }
            case .confirm(let action):
                AppConfirmDialog(title: action.title(ticket.externalKey), message: action.message(source: entity?.sourceBranch, target: entity?.targetBranch),
                                 confirmLabel: action.confirmLabel, destructive: action.destructive,
                                 onConfirm: { dialog = nil; run(action.action) }, onCancel: { dialog = nil })
            }
        }
    }

    private var entity: GitLabItemEntity? { if case .gitlabItem(let g)? = ticket.providerEntity { g } else { nil } }

    /// A compact bordered icon + label button of the header's action row.
    private func button(_ image: String, _ label: String, action: @escaping () -> Void) -> some View {
        AppButton(label, systemImage: image, kind: .secondary, action: action).disabled(busy).opacity(busy ? 0.5 : 1)
    }

    private func run(_ action: GitlabMrAction) {
        busy = true
        let t = ticket
        let isMr = (t.externalType ?? "").lowercased() == "mergerequest"
        let runner = GitlabActionRunner(service: ctx.mrService)
        Task {
            // Issues close / reopen through the same service calls as MRs.
            let res = await runner.perform(action, t)
            busy = false
            switch res {
            case .success: toasts?.show(isMr ? runner.successMessage(action, t) : issueMessage(action, t))
            case .failure(let f): toasts?.show(GitlabActionRunner.failureMessage(f), kind: .error)
            }
        }
    }

    private func issueMessage(_ action: GitlabMrAction, _ t: Ticket) -> String {
        action == .reopen ? appFormat("taskDetailReopened", "Reopened %1$@", "#\(t.externalKey)") : appFormat("taskDetailClosed", "Closed %1$@", "#\(t.externalKey)")
    }
}

enum GitlabActionDialog: Identifiable {
    case users(multiple: Bool)
    case confirm(GitlabMrConfirm)
    var id: String {
        switch self { case .users(let m): m ? "reviewers" : "assign"; case .confirm(let a): "confirm-\(a.id)" }
    }
}
