import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/detail/gitlab_mr_outcome_panel.dart
/// How a finished MR ended, as GitLab shows it: "Merged by X" with Revert / Cherry-pick (handed to the web page, whose
/// branch-picking flow creates a new MR) and the merge details, or "Closed by X" with Reopen. Nothing while still open.
struct GitlabMrOutcomePanel: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    let entity: GitLabItemEntity
    let commands: GitlabMrCommands
    let dateFormat: String

    var body: some View {
        let c = theme.colors
        let url = ticket.url ?? ""
        switch GitlabMrPhase.of(ticket, entity) {
        case .merged:
            GitlabMrWidgetCard(
                systemImage: "arrow.triangle.merge", iconColor: c.violet, tint: c.violet,
                title: AnyView(GitlabByLine(message: { appFormat("mrMergedBy", "Merged by %1$@ %2$@", $0, $1) }, name: entity.mergedBy,
                                            at: entity.mergedAt, fallback: appString("gitlabColMerged", "Merged"), dateFormat: dateFormat)),
                actions: url.isEmpty ? [] : [AnyView(AppButton(appString("mrRevert", "Revert"), kind: .ghost) { openLinkExternally(url, inApp: false) }),
                                             AnyView(AppButton(appString("mrCherryPick", "Cherry-pick"), kind: .ghost) { openLinkExternally(url, inApp: false) })],
                details: AnyView(GitlabMergedDetails(entity: entity)))
        case .closed:
            GitlabMrWidgetCard(
                systemImage: "xmark.circle", iconColor: c.red,
                title: AnyView(GitlabByLine(message: { appFormat("mrClosedBy", "Closed by %1$@ %2$@", $0, $1) }, name: entity.closedBy,
                                            at: entity.closedAt, fallback: appString("gitlabColClosed", "Closed"), dateFormat: dateFormat)),
                actions: [AnyView(GitlabMrButton(label: appString("reopenMergeRequest", "Reopen merge request"), secondary: true,
                                                 loading: commands.busy == .reopen, disabled: commands.busy != nil, action: commands.reopen))])
        default: EmptyView()
        }
    }
}

/// "Merged by **name** time" — the name in the accent, the time muted; just `fallback` when the provider didn't say who.
private struct GitlabByLine: View {
    @Environment(\.appTheme) private var theme
    let message: (String, String) -> String
    let name: String?
    let at: Date?
    let fallback: String
    let dateFormat: String

    var body: some View {
        let name = name ?? ""
        if name.isEmpty { Text(fallback) } else {
            let when = formatWhen(at, format: dateFormat)
            Text(templateRuns(slots: 2) { message($0[0], $0[1]) }.reduce(AttributedString()) { acc, run in
                var part = AttributedString(run.slot == 0 ? name : run.slot == 1 ? when : run.text)
                if run.slot == 0 { part.foregroundColor = theme.colors.accent; part.font = theme.typography.bodyStrong }
                else if run.slot == 1 { part.foregroundColor = theme.colors.tx3; part.font = theme.typography.body }
                return acc + part
            })
        }
    }
}

/// "Changes merged into `target` with `sha`.", whether the commits were squashed, and whether the source branch went too.
private struct GitlabMergedDetails: View {
    @Environment(\.appTheme) private var theme
    let entity: GitLabItemEntity

    var body: some View {
        let c = theme.colors
        let target = entity.targetBranch ?? ""
        let sha = entity.mergeCommitSha ?? entity.squashCommitSha ?? ""
        VStack(alignment: .leading, spacing: 0) {
            Text(appString("mergeDetails", "Merge details")).font(theme.typography.label).foregroundStyle(c.tx)
            if !target.isEmpty && !sha.isEmpty {
                GitlabMrDetailBullet {
                    Text(templateRuns(slots: 2) { appFormat("mrChangesMergedInto", "Changes merged into %1$@ with %2$@.", $0[0], $0[1]) }
                        .reduce(AttributedString()) { acc, run in
                            var part = AttributedString(run.slot == 0 ? target : run.slot == 1 ? String(sha.prefix(8)) : run.text)
                            if let slot = run.slot { part.font = theme.typography.mono; part.foregroundColor = slot == 1 ? c.accent : c.tx }
                            return acc + part
                        })
                }
            }
            if !(entity.squashCommitSha ?? "").isEmpty { GitlabMrDetailBullet { Text(appString("mrCommitsSquashed", "Commits were squashed.")) } }
            if entity.removeSourceBranch ?? false { GitlabMrDetailBullet { Text(appString("mrSourceBranchDeleted", "Deleted the source branch.")) } }
        }
    }
}
