import CoreDomain
import Foundation

/// Ported from: lib/tools/github/data/repositories/github_adapter.dart ("GitHub-specific" section)
extension GitHubProviderAdapter: GitHubPrAdapter {
    /// All recent issues OR PRs for one repo — the board's per-repo slice. Fetches the most-recently-updated items
    /// (`state=all`, `sort=updated`) so the lifecycle columns show recent merged/closed activity. `/issues` also
    /// returns PRs, so those are filtered out of the issue slice.
    public func listRepoItems(repo: String, pullRequests: Bool) async -> Outcome<[Ticket]> {
        await perform {
            if pullRequests {
                return try await self.client.repoPulls(repo, state: "all", sort: "updated", direction: "desc", maxPages: 2)
                    .map { normalizeGitHubPull($0, accountId: self.accountId, repoPath: repo) }
            }
            return try await self.client.repoIssues(repo, state: "all", sort: "updated", direction: "desc", maxPages: 2)
                .filter { !$0.isPullRequest }
                .map { normalizeGitHubIssue($0, accountId: self.accountId, repoPath: repo) }
        }
    }

    /// Pull requests assigned to me OR requesting my review, across all repos (deduped).
    public func listMyPullRequests() async -> Outcome<[Ticket]> {
        await perform {
            async let assigned = self.client.assignedPulls()
            async let review = self.client.reviewPulls()
            var byId = OrderedTickets()
            try await (assigned + review).forEach { byId.set(normalizeGitHubPullFromIssue($0, accountId: self.accountId)) }
            return byId.values
        }
    }

    /// Close / reopen an issue or PR via the issues `state` field (a PR is an issue, so this works for both).
    public func closeItem(_ ticket: Ticket) async -> Outcome<Bool> { await setState(ticket, "closed") }
    public func reopenItem(_ ticket: Ticket) async -> Outcome<Bool> { await setState(ticket, "open") }

    public func mergePull(_ ticket: Ticket) async -> Outcome<Bool> {
        await perform { try await self.client.mergePull(self.repoRef(ticket), ticket.externalKey); return true }
    }

    /// Update a PR branch with its base ("Update branch"; resolves a `behind` state — GitHub has no API rebase).
    public func updateBranch(_ ticket: Ticket) async -> Outcome<Bool> {
        await perform { try await self.client.updateBranch(self.repoRef(ticket), ticket.externalKey); return true }
    }

    /// Request `logins` as reviewers on a PR (additive — GitHub ignores logins already requested; removing a
    /// reviewer isn't supported through this path).
    public func setReviewers(_ ticket: Ticket, logins: [String]) async -> Outcome<Bool> {
        await perform {
            if !logins.isEmpty { try await self.client.requestReviewers(self.repoRef(ticket), ticket.externalKey, logins) }
            return true
        }
    }

    /// Repo members the ticket can be assigned to (GitHub has no account-wide assignable list).
    public func listRepoAssignees(_ ticket: Ticket) async -> Outcome<[ProviderUser]> {
        await perform {
            var seen = Set<String>()
            var out: [ProviderUser] = []
            for u in try await self.client.assignees(self.repoRef(ticket)) {
                guard let login = u.login, !login.isEmpty, seen.insert(login).inserted else { continue }
                out.append(ProviderUser(account: login, displayName: u.display))
            }
            return out.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        }
    }

    /// Commits on a pull request (detail view).
    public func listPullCommits(_ ticket: Ticket) async -> Outcome<[RepoCommit]> {
        await perform {
            try await self.client.pullCommits(self.repoRef(ticket), ticket.externalKey).map { r in
                let sha = r.sha ?? ""
                return RepoCommit(
                    sha: sha, shortSha: sha.count >= 7 ? String(sha.prefix(7)) : sha,
                    title: (r.commit?.message ?? "").split(separator: "\n", omittingEmptySubsequences: false).first
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? "",
                    author: r.commit?.author?.name, date: parseGitHubDate(r.commit?.author?.date))
            }
        }
    }

    /// Changed files on a pull request (detail view).
    public func listPullFiles(_ ticket: Ticket) async -> Outcome<[RepoFileChange]> {
        await perform {
            try await self.client.pullFiles(self.repoRef(ticket), ticket.externalKey).map {
                RepoFileChange(path: $0.filename ?? "", additions: $0.additions ?? 0, deletions: $0.deletions ?? 0,
                               status: $0.status, diff: $0.patch)
            }
        }
    }

    private func setState(_ ticket: Ticket, _ state: String) async -> Outcome<Bool> {
        await perform { try await self.client.updateIssue(self.repoRef(ticket), ticket.externalKey, state: state); return true }
    }
}
