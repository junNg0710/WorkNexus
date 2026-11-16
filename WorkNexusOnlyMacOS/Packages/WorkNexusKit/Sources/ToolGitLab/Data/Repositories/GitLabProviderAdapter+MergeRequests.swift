import CoreDomain
import Foundation

/// Ported from: lib/tools/gitlab/data/repositories/gitlab_adapter.dart ("GitLab-specific" section)
extension GitLabProviderAdapter: GitLabMrAdapter {
    public func serverVersion() async -> String? { await client.version() }

    /// All recent issues OR MRs for one project — the dedicated board's per-project slice. Fetches the ~200
    /// most-recently-updated items (`state=all`, `order_by=updated_at`) so the lifecycle columns show recent
    /// merged/closed activity, not just open work.
    public func listProjectItems(projectId: String, mergeRequests: Bool) async -> Outcome<[Ticket]> {
        await perform {
            if mergeRequests {
                return try await self.client.projectMergeRequests(projectId, state: "all", orderBy: "updated_at", sort: "desc", maxPages: 2)
                    .map { normalizeGitLabMergeRequest($0, accountId: self.accountId) }
            }
            return try await self.client.projectIssues(projectId, state: "all", orderBy: "updated_at", sort: "desc", maxPages: 2)
                .map { normalizeGitLabIssue($0, accountId: self.accountId) }
        }
    }

    /// Merge requests assigned to me OR awaiting my review, across all projects (deduped).
    public func listMyMergeRequests() async -> Outcome<[Ticket]> {
        await perform {
            async let assigned = self.client.assignedMergeRequests()
            async let me = self.client.currentUser()
            let (a, user) = try await (assigned, me)
            var review: [GitLabMergeRequest] = []
            if let username = user.username { review = try await self.client.reviewMergeRequests(username: username) }
            var byId = OrderedTickets()
            (a + review).forEach { byId.set(normalizeGitLabMergeRequest($0, accountId: self.accountId)) }
            return byId.values
        }
    }

    public func closeIssue(_ ticket: Ticket) async -> Outcome<Bool> { await issueStateEvent(ticket, "close") }
    public func reopenIssue(_ ticket: Ticket) async -> Outcome<Bool> { await issueStateEvent(ticket, "reopen") }
    public func closeMergeRequest(_ ticket: Ticket) async -> Outcome<Bool> { await mrStateEvent(ticket, "close") }
    public func reopenMergeRequest(_ ticket: Ticket) async -> Outcome<Bool> { await mrStateEvent(ticket, "reopen") }

    public func mergeMergeRequest(_ ticket: Ticket, squash: Bool?, removeSourceBranch: Bool?) async -> Outcome<Bool> {
        await perform {
            try await self.client.mergeMergeRequest(self.projectRef(ticket), ticket.externalKey, squash: squash,
                                                    shouldRemoveSourceBranch: removeSourceBranch)
            return true
        }
    }

    public func approveMergeRequest(_ ticket: Ticket) async -> Outcome<Bool> {
        await perform { try await self.client.approveMergeRequest(self.projectRef(ticket), ticket.externalKey); return true }
    }

    public func unapproveMergeRequest(_ ticket: Ticket) async -> Outcome<Bool> {
        await perform { try await self.client.unapproveMergeRequest(self.projectRef(ticket), ticket.externalKey); return true }
    }

    /// Toggle draft by rewriting the title prefix. Reads the live title first so a stale cached one never
    /// overwrites an edit made on the web.
    public func setMergeRequestDraft(_ ticket: Ticket, draft: Bool) async -> Outcome<Bool> {
        await perform {
            let ref = self.projectRef(ticket)
            let mr = try await self.client.mergeRequest(ref, ticket.externalKey)
            let title = mr.title ?? ticket.title
            try await self.client.updateMergeRequest(ref, ticket.externalKey, title: draft ? draftTitle(title) : readyTitle(title))
            return true
        }
    }

    /// Rebase onto the target branch. GitLab answers 202 and rebases in the background, so this waits for
    /// `rebase_in_progress` to clear; a failed rebase (e.g. conflicts) comes back as its `merge_error`.
    public func rebaseMergeRequest(_ ticket: Ticket) async -> Outcome<Bool> {
        let res: Outcome<String?> = await perform {
            let ref = self.projectRef(ticket), iid = ticket.externalKey
            try await self.client.rebaseMergeRequest(ref, iid)
            for _ in 0..<Self.rebasePollLimit {
                try await Task.sleep(for: self.rebasePollInterval)
                let mr = try await self.client.mergeRequest(ref, iid, includeRebaseInProgress: true)
                if mr.rebaseInProgress != true { return mr.mergeError }
            }
            return nil
        }
        switch res {
        case .failure(let f): return .failure(f)
        case .success(let error):
            if let error, !error.isEmpty { return .failure(.validation(error)) }
            return .success(true)
        }
    }

    /// Sets the MR reviewers (replaces the current set), resolving logins to member ids via the project members.
    public func setReviewers(_ ticket: Ticket, logins: [String]) async -> Outcome<Bool> {
        await perform {
            let ref = self.projectRef(ticket)
            let selected = Set(logins)
            let ids = try await self.client.members(ref).compactMap { m -> Int? in
                guard let name = m.username, let id = m.id, selected.contains(name) else { return nil }
                return id
            }
            try await self.client.updateMergeRequest(ref, ticket.externalKey, reviewerIds: ids)
            return true
        }
    }

    public func listProjectLabels(_ ticket: Ticket) async -> Outcome<[ProviderLabelOption]> {
        await perform {
            try await self.client.projectLabels(self.projectRef(ticket))
                .map { ProviderLabelOption(name: $0.name, color: $0.color) }
                .sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
    }

    public func setLabels(_ ticket: Ticket, labels: [String]) async -> Outcome<Bool> {
        await perform { try await self.client.updateMergeRequest(self.projectRef(ticket), ticket.externalKey, labels: labels); return true }
    }

    public func listProjectMilestones(_ ticket: Ticket) async -> Outcome<[ProviderMilestoneOption]> {
        await perform {
            try await self.client.projectMilestones(self.projectRef(ticket)).map {
                ProviderMilestoneOption(id: $0.id, title: $0.title ?? "#\($0.iid ?? $0.id)")
            }
        }
    }

    /// `nil` clears the milestone (GitLab takes 0 for "none").
    public func setMilestone(_ ticket: Ticket, milestoneId: Int?) async -> Outcome<Bool> {
        await perform {
            try await self.client.updateMergeRequest(self.projectRef(ticket), ticket.externalKey, milestoneId: milestoneId ?? 0)
            return true
        }
    }

    public func updateTimeTracking(_ ticket: Ticket, estimate: String?, spent: String?, resetEstimate: Bool, resetSpent: Bool) async -> Outcome<Bool> {
        await perform {
            let ref = self.projectRef(ticket), iid = ticket.externalKey
            if resetEstimate { try await self.client.resetMergeRequestTimeEstimate(ref, iid) }
            else if let e = estimate?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
                try await self.client.setMergeRequestTimeEstimate(ref, iid, e)
            }
            if resetSpent { try await self.client.resetMergeRequestSpentTime(ref, iid) }
            else if let s = spent?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                try await self.client.addMergeRequestSpentTime(ref, iid, s)
            }
            return true
        }
    }

    /// Project members the ticket can be assigned to (GitLab has no account-wide assignable list).
    public func listProjectMembers(_ ticket: Ticket) async -> Outcome<[ProviderUser]> {
        await perform {
            var seen = Set<String>()
            var users: [ProviderUser] = []
            for m in try await self.client.members(self.projectRef(ticket)) {
                guard let account = m.username, !account.isEmpty, seen.insert(account).inserted else { continue }
                users.append(ProviderUser(account: account, displayName: m.display, avatarUrl: m.avatarUrl))
            }
            return users.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        }
    }

    /// Commits on a merge request (detail view).
    public func listMergeRequestCommits(_ ticket: Ticket) async -> Outcome<[RepoCommit]> {
        await perform {
            try await self.client.mergeRequestCommits(self.projectRef(ticket), ticket.externalKey).map { r in
                RepoCommit(sha: r.id ?? "", shortSha: r.shortId ?? r.id ?? "",
                           title: (r.title ?? r.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                           author: r.authorName, date: parseGitLabDate(r.authoredDate ?? r.createdAt))
            }
        }
    }

    /// Per-file diffs on a merge request (detail view).
    public func listMergeRequestChanges(_ ticket: Ticket) async -> Outcome<[RepoFileChange]> {
        await perform {
            try await self.client.mergeRequestDiffs(self.projectRef(ticket), ticket.externalKey).map { r in
                let path = (r.newPath.map { $0.isEmpty ? nil : $0 } ?? nil) ?? r.oldPath ?? ""
                let counts = countDiffLines(r.diff)
                let status = r.newFile == true ? "added" : r.deletedFile == true ? "deleted" : r.renamedFile == true ? "renamed" : "modified"
                return RepoFileChange(path: path, additions: counts.additions, deletions: counts.deletions, status: status, diff: r.diff)
            }
        }
    }

    private func issueStateEvent(_ ticket: Ticket, _ event: String) async -> Outcome<Bool> {
        await perform { try await self.client.updateIssue(self.projectRef(ticket), ticket.externalKey, stateEvent: event); return true }
    }

    private func mrStateEvent(_ ticket: Ticket, _ event: String) async -> Outcome<Bool> {
        await perform { try await self.client.updateMergeRequest(self.projectRef(ticket), ticket.externalKey, stateEvent: event); return true }
    }
}
