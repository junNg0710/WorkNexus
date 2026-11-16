import Foundation

/// Ported from: lib/tools/gitlab/data/datasources/gitlab_client.dart (mutations section)
extension GitLabClient {
    func updateIssue(_ projectId: String, _ iid: String, assigneeIds: [Int]? = nil, stateEvent: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let assigneeIds { body["assignee_ids"] = assigneeIds }
        if let stateEvent { body["state_event"] = stateEvent }
        try await sendVoid("PUT", "/projects/\(projectId)/issues/\(iid)", body: body)
    }

    func updateMergeRequest(_ projectId: String, _ iid: String, assigneeIds: [Int]? = nil, reviewerIds: [Int]? = nil,
                            labels: [String]? = nil, milestoneId: Int? = nil, stateEvent: String? = nil,
                            title: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let title { body["title"] = title }
        if let assigneeIds { body["assignee_ids"] = assigneeIds }
        if let reviewerIds { body["reviewer_ids"] = reviewerIds }
        if let labels { body["labels"] = labels.joined(separator: ",") }
        if let milestoneId { body["milestone_id"] = milestoneId }
        if let stateEvent { body["state_event"] = stateEvent }
        try await sendVoid("PUT", "/projects/\(projectId)/merge_requests/\(iid)", body: body)
    }

    func setMergeRequestTimeEstimate(_ projectId: String, _ iid: String, _ duration: String) async throws {
        try await sendVoid("POST", "/projects/\(projectId)/merge_requests/\(iid)/time_estimate", body: ["duration": duration])
    }

    func resetMergeRequestTimeEstimate(_ projectId: String, _ iid: String) async throws {
        try await sendVoid("POST", "/projects/\(projectId)/merge_requests/\(iid)/reset_time_estimate")
    }

    func addMergeRequestSpentTime(_ projectId: String, _ iid: String, _ duration: String) async throws {
        try await sendVoid("POST", "/projects/\(projectId)/merge_requests/\(iid)/add_spent_time", body: ["duration": duration])
    }

    func resetMergeRequestSpentTime(_ projectId: String, _ iid: String) async throws {
        try await sendVoid("POST", "/projects/\(projectId)/merge_requests/\(iid)/reset_spent_time")
    }

    /// Merge a merge request; nil options keep the MR's own settings.
    func mergeMergeRequest(_ projectId: String, _ iid: String, squash: Bool? = nil, shouldRemoveSourceBranch: Bool? = nil) async throws {
        var body: [String: Any] = [:]
        if let squash { body["squash"] = squash }
        if let shouldRemoveSourceBranch { body["should_remove_source_branch"] = shouldRemoveSourceBranch }
        try await sendVoid("PUT", "/projects/\(projectId)/merge_requests/\(iid)/merge", body: body)
    }

    func approveMergeRequest(_ projectId: String, _ iid: String) async throws {
        try await sendVoid("POST", "/projects/\(projectId)/merge_requests/\(iid)/approve")
    }

    func unapproveMergeRequest(_ projectId: String, _ iid: String) async throws {
        try await sendVoid("POST", "/projects/\(projectId)/merge_requests/\(iid)/unapprove")
    }

    func mergeRequestApprovals(_ projectId: String, _ iid: String) async throws -> GitLabMrApprovals {
        try await getObject("/projects/\(projectId)/merge_requests/\(iid)/approvals", as: GitLabMrApprovals.self)
    }

    /// Rebase onto the target branch (`PUT …/rebase`, answered 202 — GitLab rebases in the background).
    func rebaseMergeRequest(_ projectId: String, _ iid: String) async throws {
        try await sendVoid("PUT", "/projects/\(projectId)/merge_requests/\(iid)/rebase")
    }

    /// Count commits present in `targetBranch` but missing from `sourceBranch` (GitLab web uses this to force a
    /// rebase on fast-forward projects even when `detailed_merge_status` says `mergeable`).
    func commitsBehindTarget(_ projectId: String, sourceBranch: String, targetBranch: String) async throws -> Int? {
        struct Ignored: Decodable { init(from decoder: Decoder) throws {} }
        struct Compare: Decodable { var commits: [Ignored]? }
        let q = [("from", sourceBranch), ("to", targetBranch), ("straight", "true"), ("per_page", "\(Self.pageLimit)")]
        return try await getObject("/projects/\(projectId)/repository/compare", query: q, as: Compare.self).commits?.count
    }
}
