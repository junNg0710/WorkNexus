import CoreDomain
import Foundation

/// Ported from: lib/tools/github/data/mappers/github_normalize.dart (+ lib/core/util/content_hash.dart)

/// The GitHub object kinds we import. `label` is stored as the ticket's `externalType`.
enum GitHubKind {
    case issue, pullRequest
    var label: String { self == .issue ? GitHubItemKind.issue.externalType : GitHubItemKind.pullRequest.externalType }
}

/// Maps a GitHub issue `state` (+ board labels) to the unified status. `open` is `todo`, promoted to
/// `inprogress` on a "doing/wip" label; a `blocked` label wins; `closed` is `done`.
func mapGitHubIssueStatus(_ state: String, _ labels: [String]) -> UnifiedStatus {
    if hasBlockedLabel(labels) { return .blocked }
    switch state {
    case "closed": return .done
    case "open": return hasInProgressLabel(labels) ? .inprogress : .todo
    default: return .todo
    }
}

/// Maps a GitHub PR (state + draft + merged + labels): `merged`/`closed` are `done`; a draft is `inprogress`; a
/// ready open PR is `review`; a `blocked` label wins over an open state.
func mapGitHubPrStatus(_ state: String, draft: Bool, merged: Bool, labels: [String]) -> UnifiedStatus {
    if merged { return .done }
    if hasBlockedLabel(labels) { return .blocked }
    switch state {
    case "closed": return .done
    default: return draft ? .inprogress : .review
    }
}

/// The raw provider status the PR board columns key on: draft / open / merged / closed (GitHub only exposes
/// open|closed plus separate draft & merged flags).
func githubPrRawStatus(state: String, draft: Bool, merged: Bool) -> String {
    if merged { return "merged" }
    if state == "closed" { return "closed" }
    return draft ? "draft" : "open"
}

/// A `priority: <level>` / `P1`-style label; absent → medium.
func mapGitHubPriority(_ labels: [String]) -> Priority { gitHubPriorityFromLabels(labels) ?? .medium }

private func hasInProgressLabel(_ labels: [String]) -> Bool {
    labels.contains { let s = $0.lowercased(); return s == "doing" || s == "wip" || s.contains("in progress") || s.contains("in-progress") }
}

private func hasBlockedLabel(_ labels: [String]) -> Bool {
    labels.contains { let s = $0.lowercased(); return s == "blocked" || s.hasSuffix("::blocked") }
}

/// Extracts an `owner/name` repo slug from an API `repository_url` (`…/repos/owner/name`) or a web `html_url`
/// (`…/owner/name/issues/1`).
func repoFromUrl(_ url: String?) -> String? {
    guard let url, !url.isEmpty, let comps = URLComponents(string: url) else { return nil }
    let segs = comps.path.split(separator: "/").map(String.init)
    if let i = segs.firstIndex(of: "repos"), segs.count >= i + 3 { return "\(segs[i + 1])/\(segs[i + 2])" }
    if segs.count >= 2 { return "\(segs[0])/\(segs[1])" }
    return nil
}

private let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
}()
private let isoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
}()

/// `DateTime.tryParse` equivalent for GitHub timestamps (ISO-8601, with or without fractional seconds).
func parseGitHubDate(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    return isoFractional.date(from: value) ?? isoPlain.date(from: value)
}

/// `DateTime.toIso8601String()` equivalent for the sync cursor (UTC, millisecond precision).
func gitHubCursor(_ date: Date) -> String { isoFractional.string(from: date) }

/// Stable, deterministic content hash (`intHash("$title $body")` in hex): 31-bit `h*31+c` over UTF-16 units.
func contentHash(title: String, body: String) -> String {
    var h = 0
    for c in "\(title) \(body)".utf16 { h = ((h &* 31) &+ Int(c)) & 0x7fffffff }
    return String(h, radix: 16)
}

private func labelNames(_ labels: [GitHubLabel]) -> [String] { labels.compactMap(\.name).filter { !$0.isEmpty } }

private func assigneeName(_ assignees: [GitHubUser]) -> String? {
    guard let first = assignees.first else { return nil }
    let name = first.display
    return name.isEmpty ? nil : name
}

private func logins(_ users: [GitHubUser]) -> [String] { users.compactMap { $0.login }.filter { !$0.isEmpty } }

/// Normalizes a GitHub issue into a unified `Ticket`. `repoPath` is passed when the fetch was repo-scoped;
/// otherwise it's parsed from the item's URLs. The id is keyed on `repo:issue:number` so the same issue keys
/// identically whether it came from the search feed or a repo fetch.
func normalizeGitHubIssue(_ e: GitHubIssue, accountId: String, repoPath: String? = nil) -> Ticket {
    let repo = repoPath ?? repoFromUrl(e.repositoryUrl ?? e.htmlUrl) ?? ""
    let title = e.title ?? "", body = e.body ?? "", state = e.state ?? "open"
    let labels = labelNames(e.labels)
    return Ticket(
        id: "\(accountId):\(repo):issue:\(e.number)", accountId: accountId, projectId: "\(accountId):\(repo)",
        providerType: .github, externalKey: "\(e.number)", title: title, body: body,
        priority: mapGitHubPriority(labels), status: mapGitHubIssueStatus(state, labels), providerStatus: state,
        sourceHash: contentHash(title: title, body: body), externalType: GitHubKind.issue.label, labels: labels,
        assignee: assigneeName(e.assignees), url: e.htmlUrl,
        createdAt: parseGitHubDate(e.createdAt), updatedAt: parseGitHubDate(e.updatedAt),
        providerEntity: .githubItem(GitHubItemEntity(
            repo: repo, author: e.user?.display, comments: e.comments,
            assignees: e.assignees.map(\.display), assigneeLogins: logins(e.assignees))))
}

/// Normalizes a PR that arrived in issue shape (the Search API returns PRs as issues). Merge state comes from the
/// `pull_request.merged_at` marker; branch/mergeability detail is fetched on demand. The id is keyed on
/// `repo:pr:number`, matching `normalizeGitHubPull`, so a PR seen via search and via `/pulls` is one ticket.
func normalizeGitHubPullFromIssue(_ e: GitHubIssue, accountId: String, repoPath: String? = nil) -> Ticket {
    let repo = repoPath ?? repoFromUrl(e.repositoryUrl ?? e.htmlUrl) ?? ""
    let title = e.title ?? "", body = e.body ?? "", state = e.state ?? "open"
    let draft = e.draft ?? false
    let merged = !(e.pullRequest?.mergedAt ?? "").isEmpty
    let labels = labelNames(e.labels)
    return Ticket(
        id: "\(accountId):\(repo):pr:\(e.number)", accountId: accountId, projectId: "\(accountId):\(repo)",
        providerType: .github, externalKey: "\(e.number)", title: title, body: body,
        priority: mapGitHubPriority(labels),
        status: mapGitHubPrStatus(state, draft: draft, merged: merged, labels: labels),
        providerStatus: githubPrRawStatus(state: state, draft: draft, merged: merged),
        sourceHash: contentHash(title: title, body: body), externalType: GitHubKind.pullRequest.label, labels: labels,
        assignee: assigneeName(e.assignees), url: e.htmlUrl,
        createdAt: parseGitHubDate(e.createdAt), updatedAt: parseGitHubDate(e.updatedAt),
        providerEntity: .githubItem(GitHubItemEntity(
            repo: repo, author: e.user?.display, draft: draft, merged: merged, comments: e.comments,
            assignees: e.assignees.map(\.display), assigneeLogins: logins(e.assignees))))
}

/// Normalizes a full pull request (from `/pulls`), including branches, merge state, and requested reviewers.
func normalizeGitHubPull(_ e: GitHubPull, accountId: String, repoPath: String? = nil) -> Ticket {
    let repo = repoPath ?? e.base?.repo?.fullName ?? repoFromUrl(e.htmlUrl) ?? ""
    let title = e.title ?? "", body = e.body ?? "", state = e.state ?? "open"
    let merged = e.isMerged
    let labels = labelNames(e.labels)
    return Ticket(
        id: "\(accountId):\(repo):pr:\(e.number)", accountId: accountId, projectId: "\(accountId):\(repo)",
        providerType: .github, externalKey: "\(e.number)", title: title, body: body,
        priority: mapGitHubPriority(labels),
        status: mapGitHubPrStatus(state, draft: e.draft, merged: merged, labels: labels),
        providerStatus: githubPrRawStatus(state: state, draft: e.draft, merged: merged),
        sourceHash: contentHash(title: title, body: body), externalType: GitHubKind.pullRequest.label, labels: labels,
        assignee: assigneeName(e.assignees), url: e.htmlUrl,
        createdAt: parseGitHubDate(e.createdAt), updatedAt: parseGitHubDate(e.updatedAt),
        providerEntity: .githubItem(GitHubItemEntity(
            repo: repo, author: e.user?.display, authorAvatarUrl: e.user?.avatarUrl, headBranch: e.head?.ref,
            baseBranch: e.base?.ref, mergeableState: e.mergeableState, draft: e.draft, merged: merged,
            comments: e.comments, additions: e.additions, deletions: e.deletions, changedFiles: e.changedFiles,
            reviewers: e.requestedReviewers.map(\.display), assignees: e.assignees.map(\.display),
            assigneeLogins: logins(e.assignees), reviewerLogins: logins(e.requestedReviewers))))
}
