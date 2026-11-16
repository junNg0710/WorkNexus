import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/tools/github/presentation/detail/github_pr_header.dart
/// The two-pane GitHub PR header: title and panel-level actions, then a metadata line — state pill,
/// "{author} requested to merge", head → base branch pills and the opened-at time.
struct GithubPrHeader: View {
    @Environment(\.appTheme) private var theme
    let nav: AppNavController
    let ticket: Ticket
    let entity: GitHubItemEntity
    let dateFormat: String
    let onClose: () -> Void
    let onSync: () -> Void

    var body: some View {
        let c = theme.colors
        let head = entity.headBranch ?? "", base = entity.baseBranch ?? ""
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            HStack(alignment: .top, spacing: theme.spacing.s8) {
                GithubBackButton(nav: nav)
                Text(ticket.title).font(theme.typography.display).foregroundStyle(c.tx).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                GithubPanelHeaderActions(url: ticket.url, onSync: onSync, onClosePanel: onClose)
            }
            FlowLayout(spacing: theme.spacing.s6, rowSpacing: theme.spacing.s6) {
                GithubStatePill(state: GithubItemState.of(ticket))
                if let author = entity.author, !author.isEmpty {
                    Text(appFormat("mrRequestedToMerge", "%1$@ requested to merge", author)).font(theme.typography.paragraph).foregroundStyle(c.tx2)
                }
                if !head.isEmpty { GithubBranchPill(branch: head) }
                if !head.isEmpty && !base.isEmpty {
                    Image(systemName: "arrow.right").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.tx3)
                }
                if !base.isEmpty { GithubBranchPill(branch: base) }
                if ticket.createdAt != nil {
                    Text(formatWhen(ticket.createdAt, format: dateFormat)).font(theme.typography.paragraph).foregroundStyle(c.tx3)
                }
            }
        }
        .padding(EdgeInsets(top: theme.spacing.s20, leading: theme.spacing.s24, bottom: theme.spacing.s14, trailing: theme.spacing.s12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: theme.borders.hairline) }
    }
}

/// A branch name in the accent on a subtle tile.
struct GithubBranchPill: View {
    @Environment(\.appTheme) private var theme
    let branch: String
    var body: some View {
        Text(branch).font(theme.typography.mono).foregroundStyle(theme.colors.accent).textSelection(.enabled)
            .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s2)
            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.sm))
    }
}
