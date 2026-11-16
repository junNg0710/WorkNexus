import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/github/presentation/detail/github_pr_overview.dart
/// The GitHub pull-request detail body: a header and the tabbed two-pane layout. Overview shows description → merge
/// widget → activity beside the metadata sidebar; Commits and Changed files live on their own tabs.
struct GithubPrOverview: View {
    let ctx: GithubContext
    let ticket: Ticket
    let entity: GitHubItemEntity
    let isSyncing: Bool
    let comments: [Comment]
    let activity: [ActivityEvent]
    let busy: Bool
    let commands: GithubPrCommands
    let onClose: () -> Void
    let onSync: () -> Void
    let onComment: (String) async -> Bool

    var body: some View {
        let service = ctx.prService, t = ticket
        TwoPaneTabbedDetail(
            isSyncing: isSyncing,
            overviewSections: [
                AnyView(GithubItemDescription(ticket: ticket, service: service).padding(.bottom, 4)),
                AnyView(GithubPrMergePanel(ticket: ticket, entity: entity, busy: busy, commands: commands)),
                AnyView(DetailActivityTimeline(comments: comments, activity: activity, onComment: onComment, onCloseItem: commands.close,
                                               canClose: GithubItemState.of(ticket).isActive)),
            ],
            header: { GithubPrHeader(nav: ctx.nav, ticket: ticket, entity: entity, dateFormat: ctx.dateFormat, onClose: onClose, onSync: onSync) },
            sidebar: { GithubPrSidebar(ctx: ctx, ticket: ticket, entity: entity) },
            commits: {
                CommitsSection { await service.listPullCommits(t).map { $0.map { SharedKit.RepoCommit(sha: $0.sha, shortSha: $0.shortSha, title: $0.title, author: $0.author, date: $0.date) } } }
            },
            changes: {
                ChangedFilesSection {
                    await service.listPullFiles(t).map {
                        $0.map { SharedKit.RepoFileChange(path: $0.path, status: $0.status, additions: $0.additions, deletions: $0.deletions, diff: $0.diff) }
                    }
                }
            })
    }
}
