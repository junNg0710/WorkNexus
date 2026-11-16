import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/detail/gitlab_detail_sections.dart
/// Dedicated metadata card for a GitLab issue / merge request. MR-only rows (reviewers, branches, merge status) are
/// omitted for issues, and empty rows everywhere.
struct GitlabDetailSections: View {
    let ctx: GitlabContext
    let ticket: Ticket
    let entity: GitLabItemEntity

    var body: some View {
        let isMr = (ticket.externalType ?? "").lowercased() == "mergerequest"
        var rows: [(String, String)] = [
            (appString("status", "Status"), statusLabel(ticket.status)),
            (appString("author", "Author"), entity.author ?? ""),
            (appString("assignee", "Assignee"), entity.assignees.joined(separator: ", ")),
        ]
        if isMr {
            rows += [(appString("reviewers", "Reviewers"), entity.reviewers.joined(separator: ", ")),
                     (appString("sourceBranch", "Source branch"), entity.sourceBranch ?? ""),
                     (appString("targetBranch", "Target branch"), entity.targetBranch ?? ""),
                     (appString("mergeStatus", "Merge status"), humanizeMergeState(entity.mergeStatus))]
        }
        rows.append((appString("updated", "Updated"), formatWhen(ticket.updatedAt, format: ctx.dateFormat)))
        return GitlabMetaCard(title: appString("details", "Details"), rows: rows,
                              valueViews: [appString("status", "Status"): AnyView(TicketStatusPill(ticket: ticket, registry: ctx.registry))])
    }
}
