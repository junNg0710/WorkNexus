import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/detail/gitlab_mr_overview.dart
/// The GitLab merge-request detail body: a header and the tabbed two-pane layout. The Overview tab follows GitLab's order
/// — description, approvals, the merge widget (or how the MR ended), activity — beside the metadata sidebar; Commits and
/// Changed files live on their own tabs.
struct GitlabMrOverview: View {
    let ctx: GitlabContext
    let ticket: Ticket
    let entity: GitLabItemEntity
    let isSyncing: Bool
    let comments: [Comment]
    let activity: [ActivityEvent]
    let commands: GitlabMrCommands
    let onClose: () -> Void
    let onSync: () -> Void
    let onComment: (String) async -> Bool

    var body: some View {
        let service = ctx.mrService, t = ticket
        let phase = GitlabMrPhase.of(ticket, entity)
        let loader: AvatarLoader = { url in await service.fetchTicketImage(t, url: url) }
        var sections: [AnyView] = [AnyView(GitlabItemDescription(ticket: ticket, service: service, baseUrl: ctx.accounts[ticket.accountId]?.baseUrl).padding(.bottom, 8))]
        if GitlabMrApprovalPanel.shows(ticket, entity) {
            sections.append(AnyView(GitlabMrApprovalPanel(ticket: ticket, entity: entity, commands: commands, avatarLoader: loader)))
        }
        sections.append(phase.isActive ? AnyView(GitlabMrMergePanel(ticket: ticket, entity: entity, commands: commands))
                                       : AnyView(GitlabMrOutcomePanel(ticket: ticket, entity: entity, commands: commands, dateFormat: ctx.dateFormat)))
        sections.append(AnyView(DetailActivityTimeline(comments: comments, activity: activity, onComment: onComment, onCloseItem: commands.close,
                                                       canClose: phase.isActive, onReopenItem: phase == .closed ? commands.reopen : nil).padding(.top, 8)))
        return TwoPaneTabbedDetail(
            isSyncing: isSyncing, overviewSections: sections, overviewCount: comments.count, changesCount: entity.changedFiles,
            header: { GitlabMrHeader(nav: ctx.nav, ticket: ticket, entity: entity, dateFormat: ctx.dateFormat, commands: commands, onClose: onClose, onSync: onSync) },
            sidebar: { GitlabMrSidebar(ctx: ctx, ticket: ticket, entity: entity) },
            commits: {
                CommitsSection { await service.listMergeRequestCommits(t).map { $0.map { SharedKit.RepoCommit(sha: $0.sha, shortSha: $0.shortSha, title: $0.title, author: $0.author, date: $0.date) } } }
            },
            changes: {
                ChangedFilesSection {
                    await service.listMergeRequestChanges(t).map {
                        $0.map { SharedKit.RepoFileChange(path: $0.path, status: $0.status, additions: $0.additions, deletions: $0.deletions, diff: $0.diff) }
                    }
                }
            })
    }
}
