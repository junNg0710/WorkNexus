import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/github/presentation/detail/github_pr_merge_panel.dart
/// The GitHub PR merge widget. Open PR → mergeable state + "Update branch" (when behind) and Merge; closed (not
/// merged) PR → Reopen; merged → hidden (the header pill conveys the terminal state). GitHub's PAT API has no approve
/// or true rebase, so neither is offered.
struct GithubPrMergePanel: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    let entity: GitHubItemEntity
    let busy: Bool
    let commands: GithubPrCommands

    var body: some View {
        let c = theme.colors
        switch GithubItemState.of(ticket) {
        case .merged: EmptyView()
        case .closed:
            GithubMergeCard {
                FlowLayout(spacing: theme.spacing.s8, rowSpacing: theme.spacing.s8) {
                    Image(systemName: "info.circle").font(.system(size: theme.sizes.icon20)).foregroundStyle(c.accent)
                    Text(appString("prClosed", "This pull request is closed.")).font(theme.typography.bodyStrong).foregroundStyle(c.tx)
                    AppButton(appString("githubReopen", "Reopen"), kind: .primary, action: commands.reopen).disabled(busy)
                }
                .padding(theme.spacing.s14)
            }
        case .open, .draft: GithubOpenMergeCard(entity: entity, busy: busy, commands: commands)
        }
    }
}

private struct GithubOpenMergeCard: View {
    @Environment(\.appTheme) private var theme
    let entity: GitHubItemEntity
    let busy: Bool
    let commands: GithubPrCommands

    var body: some View {
        let c = theme.colors
        let status = humanizeMergeState(entity.mergeableState)
        let needsUpdate = githubNeedsBranchUpdate(entity)
        let statusLine = appFormat("mergeStatusValue", "Merge status: %1$@", status)
        GithubMergeCard {
            VStack(alignment: .leading, spacing: 0) {
                FlowLayout(spacing: theme.spacing.s8, rowSpacing: theme.spacing.s8) {
                    Image(systemName: needsUpdate ? "minus.circle" : "info.circle").font(.system(size: theme.sizes.icon20))
                        .foregroundStyle(needsUpdate ? c.amber : c.accent)
                    Text(needsUpdate ? appString("prBehindBase", "This branch is out of date with the base branch.")
                                     : (status.isEmpty ? appString("mergeReady", "Ready to merge") : statusLine))
                        .font(theme.typography.bodyStrong).foregroundStyle(c.tx)
                    if needsUpdate { AppButton(appString("updateBranch", "Update branch"), kind: .secondary, action: commands.updateBranch).disabled(busy) }
                    AppButton(appString("githubMerge", "Merge"), kind: .primary, action: commands.merge).disabled(busy)
                }
                .padding(theme.spacing.s14)
                VStack(alignment: .leading, spacing: theme.spacing.s4) {
                    Text(appString("mergeDetails", "Merge details")).font(theme.typography.bodyStrong).foregroundStyle(c.tx)
                    if let head = entity.headBranch, !head.isEmpty, let base = entity.baseBranch, !base.isEmpty { GithubDetailBullet("\(head) → \(base)") }
                    if !status.isEmpty { GithubDetailBullet(statusLine) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(theme.spacing.s14)
                .background(c.panel2)
                .overlay(alignment: .top) { Rectangle().fill(c.line).frame(height: theme.borders.hairline) }
            }
        }
    }
}

/// The bordered card shell of a merge-request widget.
private struct GithubMergeCard<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.card, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}

private struct GithubDetailBullet: View {
    @Environment(\.appTheme) private var theme
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(verbatim: "• \(text)").font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2) }
}
