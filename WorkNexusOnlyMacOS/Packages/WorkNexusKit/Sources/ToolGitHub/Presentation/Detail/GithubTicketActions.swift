import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/tools/github/presentation/detail/github_ticket_actions.dart
/// The action buttons in the detail header: Assign, plus Close / Reopen (issues) or Reviewers / Update branch / Merge /
/// Close / Reopen (PRs), gated on the raw provider status and mergeable state. Merge, Close and Update branch ask first;
/// actions apply optimistically and report a toast; a merged PR is terminal (no state actions).
struct GithubActions: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let ctx: GithubContext
    let ticket: Ticket
    @State private var busy = false
    @State private var dialog: GithubActionDialog?

    var body: some View {
        let isPr = (ticket.externalType ?? "").lowercased() == "pullrequest"
        let raw = ticket.providerStatus.lowercased()
        let closed = raw == "closed", active = raw != "closed" && raw != "merged"
        var needsUpdate = false
        if case .githubItem(let g)? = ticket.providerEntity { needsUpdate = isPr && active && githubNeedsBranchUpdate(g) }
        return FlowLayout(spacing: theme.spacing.s8, rowSpacing: theme.spacing.s8) {
            GithubActionButton(systemImage: "person.badge.plus", label: appString("assign", "Assign"), disabled: busy) { dialog = .users(multiple: false) }
            if isPr && active {
                GithubActionButton(systemImage: "square.and.pencil", label: appString("reviewers", "Reviewers"), disabled: busy) { dialog = .users(multiple: true) }
            }
            if needsUpdate {
                GithubActionButton(systemImage: "arrow.triangle.2.circlepath", label: appString("updateBranch", "Update branch"), disabled: busy) { dialog = .confirm(.updateBranch) }
            }
            if isPr && active {
                GithubActionButton(systemImage: "arrow.triangle.merge", label: appString("githubMerge", "Merge"), disabled: busy) { dialog = .confirm(.merge) }
            }
            if active {
                GithubActionButton(systemImage: "checkmark.circle", label: appString("close", "Close"), disabled: busy) { dialog = .confirm(.close) }
            }
            if closed {
                GithubActionButton(systemImage: "arrow.counterclockwise", label: appString("githubReopen", "Reopen"), disabled: busy) { run(.reopen) }
            }
        }
        .sheet(item: $dialog) { d in
            switch d {
            case .users(let multiple): GithubAssignDialog(ctx: ctx, ticket: ticket, multiple: multiple) { dialog = nil }
            case .confirm(let action):
                AppConfirmDialog(title: action.title(ticket.externalKey), message: action.message(head: head, base: base),
                                 confirmLabel: action.confirmLabel, destructive: action.destructive,
                                 onConfirm: { dialog = nil; run(action.command) }, onCancel: { dialog = nil })
            }
        }
    }

    private var head: String? { if case .githubItem(let g)? = ticket.providerEntity { g.headBranch } else { nil } }
    private var base: String? { if case .githubItem(let g)? = ticket.providerEntity { g.baseBranch } else { nil } }

    private func run(_ command: GithubPrCommand) {
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

enum GithubActionDialog: Identifiable {
    case users(multiple: Bool)
    case confirm(GithubPrConfirm)
    var id: String {
        switch self { case .users(let m): m ? "reviewers" : "assign"; case .confirm(let a): "confirm-\(a)" }
    }
}

/// A compact bordered icon + label button of the header's action row.
struct GithubActionButton: View {
    @Environment(\.appTheme) private var theme
    let systemImage: String; let label: String; let disabled: Bool; let action: () -> Void
    var body: some View {
        AppButton(label, systemImage: systemImage, kind: .secondary, action: action).disabled(disabled).opacity(disabled ? 0.5 : 1)
    }
}
