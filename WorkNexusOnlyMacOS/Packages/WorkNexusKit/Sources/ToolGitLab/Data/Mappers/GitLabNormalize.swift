import CoreDomain
import Foundation

/// Ported from: lib/tools/gitlab/data/mappers/gitlab_normalize.dart (+ lib/core/util/content_hash.dart)

/// The GitLab object kinds we import. `marker` is the reference separator in `references.full`
/// (`group/web#42` for issues, `group/web!42` for MRs).
enum GitLabKind {
    case issue, mergeRequest
    var label: String { self == .issue ? GitLabItemKind.issue.externalType : GitLabItemKind.mergeRequest.externalType }
    var marker: String { self == .issue ? "#" : "!" }
}

/// Maps a GitLab issue `state` (+ board labels) to the unified status. `opened` is `todo`, promoted to
/// `inprogress` when a "doing/wip" label is present; a `blocked` label wins; `closed` is `done`.
func mapGitLabIssueStatus(_ state: String, _ labels: [String]) -> UnifiedStatus {
    if hasBlockedLabel(labels) { return .blocked }
    switch state {
    case "closed": return .done
    case "opened": return hasInProgressLabel(labels) ? .inprogress : .todo
    default: return .todo
    }
}

/// Maps a GitLab MR state (+ draft + labels): `draft` is `inprogress`; a ready `opened` MR is `review`;
/// `merged`/`closed` are `done`; a `blocked` label wins.
func mapGitLabMrStatus(_ state: String, _ draft: Bool, _ labels: [String]) -> UnifiedStatus {
    if hasBlockedLabel(labels) { return .blocked }
    switch state {
    case "merged", "closed": return .done
    case "locked": return .blocked
    default: return draft ? .inprogress : .review
    }
}

/// A scoped `priority::<level>` label; absent → medium.
func mapGitLabPriority(_ labels: [String]) -> Priority { gitLabPriorityFromLabels(labels) ?? .medium }

private func hasInProgressLabel(_ labels: [String]) -> Bool {
    labels.contains {
        let s = $0.lowercased()
        return s == "doing" || s == "wip" || s.contains("in progress") || s.contains("in-progress")
            || s.hasSuffix("::doing") || s.hasSuffix("::in progress")
    }
}

private func hasBlockedLabel(_ labels: [String]) -> Bool {
    labels.contains { let s = $0.lowercased(); return s == "blocked" || s.hasSuffix("::blocked") }
}

/// The full project path (e.g. `group/web`) from a `references.full` (`group/web#42`), falling back to the
/// numeric project id.
func projectPathFrom(_ full: String?, _ marker: String, _ projectId: Int) -> String {
    if let full, let r = full.range(of: marker, options: .backwards) {
        let path = full[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
        if !path.isEmpty { return path }
    }
    return "\(projectId)"
}

private let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
}()
private let isoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
}()

/// `DateTime.tryParse` equivalent for GitLab timestamps (ISO-8601, with or without fractional seconds).
func parseGitLabDate(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    return isoFractional.date(from: value) ?? isoPlain.date(from: value)
}

/// `DateTime.toIso8601String()` equivalent for the sync cursor (UTC, millisecond precision).
func gitLabCursor(_ date: Date) -> String { isoFractional.string(from: date) }

/// Stable, deterministic content hash (`intHash("$title $body")` in hex): 31-bit `h*31+c` over UTF-16 units.
func contentHash(title: String, body: String) -> String {
    var h = 0
    for c in "\(title) \(body)".utf16 { h = ((h &* 31) &+ Int(c)) & 0x7fffffff }
    return String(h, radix: 16)
}

private func assigneeName(_ assignees: [GitLabUser]) -> String? {
    guard let first = assignees.first else { return nil }
    let name = first.display
    return name.isEmpty ? nil : name
}

private func logins(_ users: [GitLabUser]) -> [String] { users.compactMap { $0.username }.filter { !$0.isEmpty } }

/// Normalizes a GitLab issue into a unified `Ticket`.
func normalizeGitLabIssue(_ e: GitLabIssue, accountId: String) -> Ticket {
    let path = projectPathFrom(e.references?.full, GitLabKind.issue.marker, e.projectId)
    let title = e.title ?? "", body = e.description ?? "", state = e.state ?? "opened"
    let names = e.labelNames
    return Ticket(
        id: "\(accountId):issue:\(e.id)", accountId: accountId, projectId: "\(accountId):\(path)",
        providerType: .gitlab, externalKey: "\(e.iid)", title: title, body: body,
        priority: mapGitLabPriority(names), status: mapGitLabIssueStatus(state, names), providerStatus: state,
        sourceHash: contentHash(title: title, body: body), externalType: GitLabKind.issue.label, labels: names,
        assignee: assigneeName(e.assignees), url: e.webUrl,
        createdAt: parseGitLabDate(e.createdAt), updatedAt: parseGitLabDate(e.updatedAt),
        providerEntity: .gitlabItem(GitLabItemEntity(
            projectPath: path, projectId: e.projectId, author: e.author?.display, upvotes: e.upvotes,
            assignees: e.assignees.map(\.display), assigneeLogins: logins(e.assignees),
            labelColors: e.labelColorMap, labelTextColors: e.labelTextColorMap)))
}

/// Normalizes a GitLab merge request into a unified `Ticket`.
func normalizeGitLabMergeRequest(_ e: GitLabMergeRequest, accountId: String) -> Ticket {
    let path = projectPathFrom(e.references?.full, GitLabKind.mergeRequest.marker, e.projectId)
    let title = e.title ?? "", body = e.description ?? "", state = e.state ?? "opened"
    let names = e.labelNames
    let approvers = e.approvals?.approvedBy ?? []
    var avatarUrls: [String: String] = [:]
    let involved: [GitLabUser?] = [e.author] + e.assignees.map { Optional($0) } + e.reviewers.map { Optional($0) }
        + [e.mergedBy, e.closedBy] + approvers.map { Optional($0) }
    for user in involved {
        let name = user?.display ?? "", avatar = user?.avatarUrl ?? ""
        if !name.isEmpty && !avatar.isEmpty { avatarUrls[name] = avatar }
    }
    // Preserve draft in the raw status so the MR board can split draft vs review.
    let rawStatus = (state == "opened" && e.draft) ? "draft" : state
    return Ticket(
        id: "\(accountId):mr:\(e.id)", accountId: accountId, projectId: "\(accountId):\(path)",
        providerType: .gitlab, externalKey: "\(e.iid)", title: title, body: body,
        priority: mapGitLabPriority(names), status: mapGitLabMrStatus(state, e.draft, names), providerStatus: rawStatus,
        sourceHash: contentHash(title: title, body: body), externalType: GitLabKind.mergeRequest.label, labels: names,
        assignee: assigneeName(e.assignees), url: e.webUrl,
        createdAt: parseGitLabDate(e.createdAt), updatedAt: parseGitLabDate(e.updatedAt),
        providerEntity: .gitlabItem(GitLabItemEntity(
            projectPath: path, projectId: e.projectId, author: e.author?.display, authorAvatarUrl: e.author?.avatarUrl,
            sourceBranch: e.sourceBranch, targetBranch: e.targetBranch,
            mergeStatus: e.detailedMergeStatus ?? e.mergeStatus, commitsBehind: e.commitsBehind, draft: e.draft,
            upvotes: e.upvotes, milestoneId: e.milestone?.id, milestoneTitle: e.milestone?.title,
            humanTimeEstimate: e.timeStats?.humanTimeEstimate, humanTotalTimeSpent: e.timeStats?.humanTotalTimeSpent,
            mergedBy: e.mergedBy?.display, mergedAt: parseGitLabDate(e.mergedAt), closedBy: e.closedBy?.display,
            closedAt: parseGitLabDate(e.closedAt), mergeCommitSha: e.mergeCommitSha, squashCommitSha: e.squashCommitSha,
            squash: e.squash, removeSourceBranch: e.shouldRemoveSourceBranch ?? e.forceRemoveSourceBranch,
            approvedBy: approvers.map(\.display), approvalsRequired: e.approvals?.approvalsRequired,
            approvalsLeft: e.approvals?.approvalsLeft, userHasApproved: e.approvals?.userHasApproved,
            userCanApprove: e.approvals?.userCanApprove, reviewers: e.reviewers.map(\.display),
            assignees: e.assignees.map(\.display), assigneeLogins: logins(e.assignees),
            userAvatarUrls: avatarUrls, labelColors: e.labelColorMap, labelTextColors: e.labelTextColorMap)))
}

/// GitLab system-note bodies carry the human summary on the first line, then may append a markdown/HTML detail
/// block. Keep just that summary line and strip markdown emphasis / stray HTML.
func gitLabActivitySummary(_ body: String) -> String {
    let line = body.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
    return line
        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        .replacingOccurrences(of: "\\*\\*|__|`", with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
}
