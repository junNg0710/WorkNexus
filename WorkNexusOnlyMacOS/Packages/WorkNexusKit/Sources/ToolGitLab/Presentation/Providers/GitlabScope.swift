import CoreDomain
import CoreTools
import Foundation
import SharedKit

/// Ported from: lib/tools/gitlab/presentation/providers/gitlab_scope.dart
/// Whether `t` is in the GitLab project `scopeId`. The sidebar scopes by the project's numeric id
/// (`ProviderProject.id`); a ticket keeps it on its entity, beside the `group/name` path its `projectId` is built from.
func gitlabTicketInProject(_ t: Ticket, _ scopeId: String) -> Bool {
    if case .gitlabItem(let g)? = t.providerEntity {
        if g.projectId.map(String.init) == scopeId || g.projectPath == scopeId { return true }
    }
    return t.projectId == scopeId
}

/// The GitLab tickets a board of `accountId` shows before the user's filters: that account's items, in project
/// `scopeId` when one is open — the same scope the section's list view applies.
func scopeGitLabTickets(_ tickets: [Ticket], accountId: String?, scopeId: String?) -> [Ticket] {
    tickets.filter {
        $0.providerType == .gitlab && (accountId == nil || $0.accountId == accountId)
            && (scopeId == nil || gitlabTicketInProject($0, scopeId!))
    }
}

/// Whether `t` is of `kind` (`externalType` is `MergeRequest` / `Issue`).
func gitlabTicketIsKind(_ t: Ticket, _ kind: GitLabItemKind) -> Bool {
    let isMr = (t.externalType ?? "").lowercased() == "mergerequest"
    return kind == .mergeRequest ? isMr : !isMr
}

/// The "All open / Draft / In review / Assigned to me" chips of the merge-request list.
enum GitlabMrChip: CaseIterable {
    case allOpen, draft, inReview, assignedToMe

    func matches(_ t: Ticket, account: Account) -> Bool {
        var entity: GitLabItemEntity?
        if case .gitlabItem(let g)? = t.providerEntity { entity = g }
        switch self {
        case .allOpen: return true
        case .draft: return entity?.draft == true
        case .inReview: return entity?.reviewers.isEmpty == false
        case .assignedToMe: return IsAssignedToMe()(t, account)
        }
    }
}

/// The state view modes of the merge-request list.
enum GitlabMrListState: String, CaseIterable {
    case open, merged, closed

    /// Dart `GitlabMrsSection` state filters, keyed off the raw status.
    func matches(_ t: Ticket) -> Bool {
        let raw = t.providerStatus.lowercased()
        switch self {
        case .merged: return raw == "merged"
        case .closed: return (t.status == .done || raw == "closed") && raw != "merged"
        case .open: return t.status != .done && raw != "merged" && raw != "closed"
        }
    }
}

/// The page of the provider the current section maps to (Dart `GitlabModule.webUrl`): the project's, else the account's
/// dashboard; the base URL defaults to gitlab.com.
func gitlabWebURL(account: Account, location: ToolLocation) -> URL? {
    let raw = account.baseUrl ?? ""
    let base = raw.isEmpty ? "https://gitlab.com" : raw
    let root = base.hasSuffix("/") ? String(base.dropLast()) : base
    let issues = location.section == GitlabSections.issues
    if let scope = location.scopeId { return URL(string: "\(root)/\(scope)/-/\(issues ? "issues" : "merge_requests")") }
    return URL(string: "\(root)/dashboard/\(issues ? "issues" : "merge_requests")")
}
