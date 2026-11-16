import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/detail/gitlab_mr_merge_panel.dart
/// The merge widget of an open MR, in GitLab's three states: blocked as a draft (→ Mark as ready), blocked behind its
/// target (→ Rebase), or mergeable (→ Merge, with the delete-source-branch / squash options). Hidden once the MR is merged
/// or closed — `GitlabMrOutcomePanel` takes over.
struct GitlabMrMergePanel: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    let entity: GitLabItemEntity
    let commands: GitlabMrCommands
    @State private var removeSourceBranch: Bool
    @State private var squash: Bool

    init(ticket: Ticket, entity: GitLabItemEntity, commands: GitlabMrCommands) {
        self.ticket = ticket; self.entity = entity; self.commands = commands
        _removeSourceBranch = State(initialValue: entity.removeSourceBranch ?? false)
        _squash = State(initialValue: entity.squash ?? false)
    }

    private struct Options: Equatable { var squash: Bool?; var remove: Bool? }

    var body: some View {
        let c = theme.colors
        let phase = GitlabMrPhase.of(ticket, entity)
        if phase.isActive {
            let isDraft = phase == .draft
            let status = humanizeMergeState(entity.mergeStatus)
            let behind = entity.commitsBehind ?? 0
            let needsRebase = gitlabMrNeedsRebase(entity)
            let mergeable = !isDraft && !needsRebase
            let statusLine = appFormat("mergeStatusValue", "Merge status: %1$@", status)
            GitlabMrWidgetCard(
                systemImage: mergeable ? "checkmark.circle" : "minus.circle", iconColor: mergeable ? c.green : (isDraft ? c.tx2 : c.red),
                title: AnyView(Text(isDraft ? appString("mergeBlockedDraft", "Merge blocked: this merge request is a draft.")
                                    : needsRebase ? appString("mergeBlockedNeedRebase", "Merge blocked — the source branch must be rebased onto the target branch.")
                                    : (status.isEmpty ? appString("mergeReady", "Ready to merge") : statusLine))),
                actions: [AnyView(primaryAction(isDraft: isDraft, needsRebase: needsRebase))],
                details: AnyView(VStack(alignment: .leading, spacing: 0) {
                    if mergeable {
                        FlowLayout(spacing: theme.spacing.s16, rowSpacing: theme.spacing.s4) {
                            Toggle(appString("deleteSourceBranch", "Delete source branch"), isOn: $removeSourceBranch)
                            Toggle(appString("squashCommits", "Squash commits"), isOn: $squash)
                        }
                        .toggleStyle(.checkbox).padding(.bottom, theme.spacing.s10)
                    }
                    Text(appString("mergeDetails", "Merge details")).font(theme.typography.label).foregroundStyle(c.tx)
                    if behind > 0 { GitlabMrDetailBullet { Text(commitsBehindText(behind)) } }
                    if let s = entity.sourceBranch, !s.isEmpty, let t = entity.targetBranch, !t.isEmpty { GitlabMrDetailBullet { Text("\(s) → \(t)") } }
                    if !status.isEmpty { GitlabMrDetailBullet { Text(statusLine) } }
                }))
            // A refresh that changed the MR's own settings (e.g. edited on the web) wins over the local toggles.
            .onChange(of: Options(squash: entity.squash, remove: entity.removeSourceBranch)) {
                removeSourceBranch = entity.removeSourceBranch ?? false; squash = entity.squash ?? false
            }
        }
    }

    @ViewBuilder private func primaryAction(isDraft: Bool, needsRebase: Bool) -> some View {
        let busy = commands.busy
        if isDraft {
            GitlabMrButton(label: appString("markAsReady", "Mark as ready"), loading: busy == .draft, disabled: busy != nil) { commands.setDraft(false) }
        } else if needsRebase {
            GitlabMrButton(label: appString("rebase", "Rebase"), loading: busy == .rebase, disabled: busy != nil, action: commands.rebase)
        } else {
            GitlabMrButton(label: appString("gitlabMerge", "Merge"), loading: busy == .merge, disabled: busy != nil) { commands.merge(squash, removeSourceBranch) }
        }
    }

    private func commitsBehindText(_ n: Int) -> String {
        n == 1 ? appString("commitsBehindTargetOne", "The source branch is 1 commit behind the target branch.")
               : appFormat("commitsBehindTargetOther", "The source branch is %1$@ commits behind the target branch.", "\(n)")
    }
}
