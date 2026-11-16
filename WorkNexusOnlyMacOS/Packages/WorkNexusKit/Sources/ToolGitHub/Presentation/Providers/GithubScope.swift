import CoreDomain
import Foundation

/// Ported from: lib/tools/github/presentation/providers/github_scope.dart
/// The repository (`owner/name`) a ticket belongs to: its entity's `repo`, else the project id.
func githubTicketRepo(_ t: Ticket) -> String? {
    if case .githubItem(let g)? = t.providerEntity { return g.repo }
    return t.projectId
}

/// The GitHub tickets a board of `accountId` shows before the user's filters: that account's items, in repository
/// `scopeId` when one is open — the same scope the section's list view applies.
func scopeGitHubTickets(_ tickets: [Ticket], accountId: String?, scopeId: String?) -> [Ticket] {
    tickets.filter {
        $0.providerType == .github && (accountId == nil || $0.accountId == accountId)
            && (scopeId == nil || githubTicketRepo($0) == scopeId)
    }
}

/// Whether `t` is of `kind` (`externalType` is `PullRequest` / `Issue`).
func githubTicketIsKind(_ t: Ticket, _ kind: GitHubItemKind) -> Bool {
    let isPr = (t.externalType ?? "").lowercased() == "pullrequest"
    return kind == .pullRequest ? isPr : !isPr
}

/// "Review requested" quick scope: the account's user is among the PR's requested reviewers. Logins first (as the
/// account knows its user); items stored before logins were kept only have the reviewers' display names.
func githubReviewRequested(_ t: Ticket, account: Account) -> Bool {
    guard case .githubItem(let g)? = t.providerEntity else { return false }
    let reviewers = g.reviewerLogins.isEmpty ? g.reviewers : g.reviewerLogins
    return reviewers.contains { $0.lowercased() == account.handle.lowercased() }
}

/// The state view modes of the pull-request list.
enum GithubPrListState: String, CaseIterable {
    case open, merged, closed

    /// Dart `GithubPullsSection` state filters (`merged` flag decides merged; closed = done but not merged).
    func matches(_ t: Ticket) -> Bool {
        var merged = false
        if case .githubItem(let g)? = t.providerEntity { merged = g.merged == true }
        switch self {
        case .merged: return merged
        case .closed: return t.status == .done && !merged
        case .open: return t.status != .done && !merged
        }
    }
}
