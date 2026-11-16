import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/github/presentation/detail/github_detail_sections.dart
/// Dedicated metadata card for a GitHub issue / pull request. PR-only rows (reviewers, branches, merge status) are
/// omitted for issues, and empty rows everywhere.
struct GithubDetailSections: View {
    let ctx: GithubContext
    let ticket: Ticket
    let entity: GitHubItemEntity

    var body: some View {
        let isPr = (ticket.externalType ?? "").lowercased() == "pullrequest"
        var rows: [(String, String)] = [
            (appString("status", "Status"), statusLabel(ticket.status)),
            (appString("author", "Author"), entity.author ?? ""),
            (appString("assignee", "Assignee"), entity.assignees.joined(separator: ", ")),
        ]
        if isPr {
            rows += [(appString("reviewers", "Reviewers"), entity.reviewers.joined(separator: ", ")),
                     (appString("sourceBranch", "Source branch"), entity.headBranch ?? ""),
                     (appString("targetBranch", "Target branch"), entity.baseBranch ?? ""),
                     (appString("mergeStatus", "Merge status"), humanizeMergeState(entity.mergeableState))]
        }
        rows.append((appString("updated", "Updated"), formatWhen(ticket.updatedAt, format: ctx.dateFormat)))
        return GithubMetaCard(title: appString("details", "Details"), rows: rows,
                              valueViews: [appString("status", "Status"): AnyView(TicketStatusPill(ticket: ticket, registry: ctx.registry))])
    }
}
