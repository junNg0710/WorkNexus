import CoreDomain
import Foundation

/// Ported from: lib/tools/gitlab/data/models/gitlab_models.dart
/// Deserialize-only DTOs for the GitLab REST v4 API (decoded with `.convertFromSnakeCase`). They never leave
/// `Data/` (rule 3.3): `GitLabNormalize` maps them to domain entities at the boundary.

struct GitLabUser: Decodable, Equatable {
    var id: Int?
    var username: String?
    var name: String?
    var avatarUrl: String?

    init(id: Int? = nil, username: String? = nil, name: String? = nil, avatarUrl: String? = nil) {
        self.id = id; self.username = username; self.name = name; self.avatarUrl = avatarUrl
    }

    /// Human-friendly display name, falling back to the username.
    var display: String {
        if let name, !name.isEmpty { return name }
        return username ?? ""
    }
}

/// A label parsed from either a bare name string or a details object (`with_labels_details=true`).
struct GitLabLabel: Decodable, Equatable {
    var name: String
    var color: String?
    var textColor: String?

    init(name: String, color: String? = nil, textColor: String? = nil) {
        self.name = name; self.color = color; self.textColor = textColor
    }

    private enum CodingKeys: String, CodingKey { case name, color, textColor }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self) {
            self.init(name: s)
            return
        }
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { self.init(name: ""); return }
        self.init(name: (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "",
                  color: (try? c.decodeIfPresent(String.self, forKey: .color)) ?? nil,
                  textColor: (try? c.decodeIfPresent(String.self, forKey: .textColor)) ?? nil)
    }
}

private func decodeLabels<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [GitLabLabel] {
    ((try? c.decodeIfPresent([GitLabLabel].self, forKey: key)) ?? nil)?.filter { !$0.name.isEmpty } ?? []
}

private func nonEmptyColors(_ labels: [GitLabLabel], _ pick: (GitLabLabel) -> String?) -> [String: String] {
    var out: [String: String] = [:]
    for l in labels { if let v = pick(l), !v.isEmpty { out[l.name] = v } }
    return out
}

struct GitLabProject: Decodable, Equatable {
    var id: Int
    var name: String?
    var pathWithNamespace: String?
    var nameWithNamespace: String?
    var webUrl: String?

    init(id: Int, name: String? = nil, pathWithNamespace: String? = nil, nameWithNamespace: String? = nil, webUrl: String? = nil) {
        self.id = id; self.name = name; self.pathWithNamespace = pathWithNamespace
        self.nameWithNamespace = nameWithNamespace; self.webUrl = webUrl
    }

    /// Display name — the namespaced name if present (e.g. `Group / Web`).
    var display: String {
        if let n = nameWithNamespace, !n.isEmpty { return n }
        return name ?? pathWithNamespace ?? "\(id)"
    }
}

struct GitLabReferences: Decodable, Equatable {
    var short: String?
    var relative: String?
    var full: String?
    init(short: String? = nil, relative: String? = nil, full: String? = nil) {
        self.short = short; self.relative = relative; self.full = full
    }
}

struct GitLabMilestone: Decodable, Equatable {
    var id: Int
    var iid: Int?
    var title: String?
    init(id: Int, iid: Int? = nil, title: String? = nil) { self.id = id; self.iid = iid; self.title = title }
}

struct GitLabTimeStats: Decodable, Equatable {
    var timeEstimate: Int?
    var totalTimeSpent: Int?
    var humanTimeEstimate: String?
    var humanTotalTimeSpent: String?
    init(timeEstimate: Int? = nil, totalTimeSpent: Int? = nil, humanTimeEstimate: String? = nil, humanTotalTimeSpent: String? = nil) {
        self.timeEstimate = timeEstimate; self.totalTimeSpent = totalTimeSpent
        self.humanTimeEstimate = humanTimeEstimate; self.humanTotalTimeSpent = humanTotalTimeSpent
    }
}

struct GitLabIssue: Decodable {
    var id: Int
    var iid: Int
    var projectId: Int
    var title: String?
    var description: String?
    var state: String?          // opened | closed
    var labels: [GitLabLabel]
    var author: GitLabUser?
    var assignees: [GitLabUser]
    var webUrl: String?
    var references: GitLabReferences?
    var upvotes: Int?
    var createdAt: String?
    var updatedAt: String?

    init(id: Int, iid: Int, projectId: Int, title: String? = nil, description: String? = nil, state: String? = nil,
         labels: [GitLabLabel] = [], author: GitLabUser? = nil, assignees: [GitLabUser] = [], webUrl: String? = nil,
         references: GitLabReferences? = nil, upvotes: Int? = nil, createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id; self.iid = iid; self.projectId = projectId; self.title = title; self.description = description
        self.state = state; self.labels = labels; self.author = author; self.assignees = assignees
        self.webUrl = webUrl; self.references = references; self.upvotes = upvotes
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, iid, projectId, title, description, state, labels, author, assignees, webUrl, references
        case upvotes, createdAt, updatedAt
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        iid = try c.decode(Int.self, forKey: .iid)
        projectId = try c.decode(Int.self, forKey: .projectId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        labels = decodeLabels(c, .labels)
        author = try c.decodeIfPresent(GitLabUser.self, forKey: .author)
        assignees = try c.decodeIfPresent([GitLabUser].self, forKey: .assignees) ?? []
        webUrl = try c.decodeIfPresent(String.self, forKey: .webUrl)
        references = try c.decodeIfPresent(GitLabReferences.self, forKey: .references)
        upvotes = try c.decodeIfPresent(Int.self, forKey: .upvotes)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    var labelNames: [String] { labels.map(\.name) }
    var labelColorMap: [String: String] { nonEmptyColors(labels, \.color) }
    var labelTextColorMap: [String: String] { nonEmptyColors(labels, \.textColor) }
}

/// `GET …/merge_requests/:iid/approvals` — who approved, how many approvals are still needed.
struct GitLabMrApprovals: Decodable, Equatable {
    var approvedBy: [GitLabUser]
    var approvalsRequired: Int?
    var approvalsLeft: Int?
    var userHasApproved: Bool
    var userCanApprove: Bool

    init(approvedBy: [GitLabUser] = [], approvalsRequired: Int? = nil, approvalsLeft: Int? = nil,
         userHasApproved: Bool = false, userCanApprove: Bool = false) {
        self.approvedBy = approvedBy; self.approvalsRequired = approvalsRequired; self.approvalsLeft = approvalsLeft
        self.userHasApproved = userHasApproved; self.userCanApprove = userCanApprove
    }

    private enum CodingKeys: String, CodingKey { case approvedBy, approvalsRequired, approvalsLeft, userHasApproved, userCanApprove }
    private struct Wrapper: Decodable { var user: GitLabUser? }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        // `approved_by` wraps each user: `[{ "user": { … } }]`.
        let wrapped = (try? c.decodeIfPresent([Wrapper].self, forKey: .approvedBy)) ?? nil
        approvedBy = (wrapped ?? []).compactMap(\.user)
        approvalsRequired = try c.decodeIfPresent(Int.self, forKey: .approvalsRequired)
        approvalsLeft = try c.decodeIfPresent(Int.self, forKey: .approvalsLeft)
        userHasApproved = try c.decodeIfPresent(Bool.self, forKey: .userHasApproved) ?? false
        userCanApprove = try c.decodeIfPresent(Bool.self, forKey: .userCanApprove) ?? false
    }
}

struct GitLabMergeRequest: Decodable {
    var id: Int
    var iid: Int
    var projectId: Int
    var title: String?
    var description: String?
    var state: String?          // opened | closed | merged | locked
    var draft: Bool
    var labels: [GitLabLabel]
    var author: GitLabUser?
    var assignees: [GitLabUser]
    var reviewers: [GitLabUser]
    var sourceBranch: String?
    var targetBranch: String?
    var mergeStatus: String?
    var detailedMergeStatus: String?
    var commitsBehind: Int?             // not from JSON — filled by the adapter
    var milestone: GitLabMilestone?
    var timeStats: GitLabTimeStats?
    var webUrl: String?
    var references: GitLabReferences?
    var upvotes: Int?
    var createdAt: String?
    var updatedAt: String?
    var mergedBy: GitLabUser?
    var mergedAt: String?
    var closedBy: GitLabUser?
    var closedAt: String?
    var mergeCommitSha: String?
    var squashCommitSha: String?
    var squash: Bool?
    var forceRemoveSourceBranch: Bool?
    var shouldRemoveSourceBranch: Bool?
    var approvals: GitLabMrApprovals?   // not from JSON — fetched separately on detail open
    var rebaseInProgress: Bool?
    var mergeError: String?

    init(id: Int, iid: Int, projectId: Int, title: String? = nil, description: String? = nil, state: String? = nil,
         draft: Bool = false, labels: [GitLabLabel] = [], author: GitLabUser? = nil, assignees: [GitLabUser] = [],
         reviewers: [GitLabUser] = [], sourceBranch: String? = nil, targetBranch: String? = nil,
         mergeStatus: String? = nil, detailedMergeStatus: String? = nil, commitsBehind: Int? = nil,
         milestone: GitLabMilestone? = nil, timeStats: GitLabTimeStats? = nil, webUrl: String? = nil,
         references: GitLabReferences? = nil, upvotes: Int? = nil, createdAt: String? = nil, updatedAt: String? = nil,
         mergedBy: GitLabUser? = nil, mergedAt: String? = nil, closedBy: GitLabUser? = nil, closedAt: String? = nil,
         mergeCommitSha: String? = nil, squashCommitSha: String? = nil, squash: Bool? = nil,
         forceRemoveSourceBranch: Bool? = nil, shouldRemoveSourceBranch: Bool? = nil,
         approvals: GitLabMrApprovals? = nil, rebaseInProgress: Bool? = nil, mergeError: String? = nil) {
        self.id = id; self.iid = iid; self.projectId = projectId; self.title = title; self.description = description
        self.state = state; self.draft = draft; self.labels = labels; self.author = author; self.assignees = assignees
        self.reviewers = reviewers; self.sourceBranch = sourceBranch; self.targetBranch = targetBranch
        self.mergeStatus = mergeStatus; self.detailedMergeStatus = detailedMergeStatus
        self.commitsBehind = commitsBehind; self.milestone = milestone; self.timeStats = timeStats
        self.webUrl = webUrl; self.references = references; self.upvotes = upvotes; self.createdAt = createdAt
        self.updatedAt = updatedAt; self.mergedBy = mergedBy; self.mergedAt = mergedAt; self.closedBy = closedBy
        self.closedAt = closedAt; self.mergeCommitSha = mergeCommitSha; self.squashCommitSha = squashCommitSha
        self.squash = squash; self.forceRemoveSourceBranch = forceRemoveSourceBranch
        self.shouldRemoveSourceBranch = shouldRemoveSourceBranch; self.approvals = approvals
        self.rebaseInProgress = rebaseInProgress; self.mergeError = mergeError
    }

    private enum CodingKeys: String, CodingKey {
        case id, iid, projectId, title, description, state, draft, labels, author, assignees, reviewers
        case sourceBranch, targetBranch, mergeStatus, detailedMergeStatus, milestone, timeStats, webUrl
        case references, upvotes, createdAt, updatedAt, mergedBy, mergedAt, closedBy, closedAt
        case mergeCommitSha, squashCommitSha, squash, forceRemoveSourceBranch, shouldRemoveSourceBranch
        case rebaseInProgress, mergeError
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        iid = try c.decode(Int.self, forKey: .iid)
        projectId = try c.decode(Int.self, forKey: .projectId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        draft = try c.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        labels = decodeLabels(c, .labels)
        author = try c.decodeIfPresent(GitLabUser.self, forKey: .author)
        assignees = try c.decodeIfPresent([GitLabUser].self, forKey: .assignees) ?? []
        reviewers = try c.decodeIfPresent([GitLabUser].self, forKey: .reviewers) ?? []
        sourceBranch = try c.decodeIfPresent(String.self, forKey: .sourceBranch)
        targetBranch = try c.decodeIfPresent(String.self, forKey: .targetBranch)
        mergeStatus = try c.decodeIfPresent(String.self, forKey: .mergeStatus)
        detailedMergeStatus = try c.decodeIfPresent(String.self, forKey: .detailedMergeStatus)
        milestone = try c.decodeIfPresent(GitLabMilestone.self, forKey: .milestone)
        timeStats = try c.decodeIfPresent(GitLabTimeStats.self, forKey: .timeStats)
        webUrl = try c.decodeIfPresent(String.self, forKey: .webUrl)
        references = try c.decodeIfPresent(GitLabReferences.self, forKey: .references)
        upvotes = try c.decodeIfPresent(Int.self, forKey: .upvotes)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        mergedBy = try c.decodeIfPresent(GitLabUser.self, forKey: .mergedBy)
        mergedAt = try c.decodeIfPresent(String.self, forKey: .mergedAt)
        closedBy = try c.decodeIfPresent(GitLabUser.self, forKey: .closedBy)
        closedAt = try c.decodeIfPresent(String.self, forKey: .closedAt)
        mergeCommitSha = try c.decodeIfPresent(String.self, forKey: .mergeCommitSha)
        squashCommitSha = try c.decodeIfPresent(String.self, forKey: .squashCommitSha)
        squash = try c.decodeIfPresent(Bool.self, forKey: .squash)
        forceRemoveSourceBranch = try c.decodeIfPresent(Bool.self, forKey: .forceRemoveSourceBranch)
        shouldRemoveSourceBranch = try c.decodeIfPresent(Bool.self, forKey: .shouldRemoveSourceBranch)
        rebaseInProgress = try c.decodeIfPresent(Bool.self, forKey: .rebaseInProgress)
        mergeError = try c.decodeIfPresent(String.self, forKey: .mergeError)
    }

    var labelNames: [String] { labels.map(\.name) }
    var labelColorMap: [String: String] { nonEmptyColors(labels, \.color) }
    var labelTextColorMap: [String: String] { nonEmptyColors(labels, \.textColor) }
}

/// A note (comment or system event). `system == true` marks an auto-generated activity note.
struct GitLabNote: Decodable, Equatable {
    var id: Int
    var body: String?
    var author: GitLabUser?
    var system: Bool
    var createdAt: String?

    init(id: Int, body: String? = nil, author: GitLabUser? = nil, system: Bool = false, createdAt: String? = nil) {
        self.id = id; self.body = body; self.author = author; self.system = system; self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, body, author, system, createdAt }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        author = try c.decodeIfPresent(GitLabUser.self, forKey: .author)
        system = try c.decodeIfPresent(Bool.self, forKey: .system) ?? false
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

/// `GET …/merge_requests/:iid/commits` row (the Dart client kept raw maps; typed here).
struct GitLabCommitRow: Decodable, Equatable {
    var id: String?
    var shortId: String?
    var title: String?
    var message: String?
    var authorName: String?
    var authoredDate: String?
    var createdAt: String?
}

/// `GET …/merge_requests/:iid/diffs` row.
struct GitLabDiffRow: Decodable, Equatable {
    var oldPath: String?
    var newPath: String?
    var diff: String?
    var newFile: Bool?
    var deletedFile: Bool?
    var renamedFile: Bool?
}
