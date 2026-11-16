import CoreDomain
import Foundation

/// Ported from: lib/tools/github/data/models/github_models.dart
/// Deserialize-only DTOs for the GitHub REST API (decoded with `.convertFromSnakeCase`). They never leave
/// `Data/` (rule 3.3): `GitHubNormalize` maps them to domain entities at the boundary. A PR *is* a kind of issue:
/// `/issues` and search return PRs too (tagged with a `pull_request` object); `/pulls` carries the richer fields.

struct GitHubUser: Decodable, Equatable {
    var login: String?
    var name: String?
    var avatarUrl: String?
    init(login: String? = nil, name: String? = nil, avatarUrl: String? = nil) {
        self.login = login; self.name = name; self.avatarUrl = avatarUrl
    }
    /// Human-friendly display name, falling back to the login.
    var display: String {
        if let name, !name.isEmpty { return name }
        return login ?? ""
    }
}

/// A repository from `GET /user/repos`; `fullName` (`owner/name`) is the canonical ref in every `/repos/…` path.
struct GitHubRepo: Decodable, Equatable {
    var fullName: String
    var name: String?
    var htmlUrl: String?
    init(fullName: String, name: String? = nil, htmlUrl: String? = nil) { self.fullName = fullName; self.name = name; self.htmlUrl = htmlUrl }
    var display: String { fullName }
}

struct GitHubLabel: Decodable, Equatable {
    var name: String?
    init(name: String? = nil) { self.name = name }
}

/// The `pull_request` marker in an issue-shaped object; `mergedAt` distinguishes merged from merely closed.
struct GitHubPullMarker: Decodable, Equatable {
    var mergedAt: String?
    var htmlUrl: String?
    init(mergedAt: String? = nil, htmlUrl: String? = nil) { self.mergedAt = mergedAt; self.htmlUrl = htmlUrl }
}

/// An issue-shaped object from the Search API or `GET /repos/:repo/issues` (carries plain issues and PRs).
struct GitHubIssue: Decodable {
    var number: Int
    var title: String?
    var body: String?
    var state: String?          // open | closed
    var draft: Bool?
    var labels: [GitHubLabel]
    var user: GitHubUser?
    var assignees: [GitHubUser]
    var htmlUrl: String?
    var repositoryUrl: String?
    var pullRequest: GitHubPullMarker?
    var comments: Int?
    var createdAt: String?
    var updatedAt: String?

    init(number: Int, title: String? = nil, body: String? = nil, state: String? = nil, draft: Bool? = nil,
         labels: [GitHubLabel] = [], user: GitHubUser? = nil, assignees: [GitHubUser] = [], htmlUrl: String? = nil,
         repositoryUrl: String? = nil, pullRequest: GitHubPullMarker? = nil, comments: Int? = nil,
         createdAt: String? = nil, updatedAt: String? = nil) {
        self.number = number; self.title = title; self.body = body; self.state = state; self.draft = draft
        self.labels = labels; self.user = user; self.assignees = assignees; self.htmlUrl = htmlUrl
        self.repositoryUrl = repositoryUrl; self.pullRequest = pullRequest; self.comments = comments
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case number, title, body, state, draft, labels, user, assignees, htmlUrl, repositoryUrl, pullRequest
        case comments, createdAt, updatedAt
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        number = try c.decode(Int.self, forKey: .number)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        draft = try c.decodeIfPresent(Bool.self, forKey: .draft)
        labels = try c.decodeIfPresent([GitHubLabel].self, forKey: .labels) ?? []
        user = try c.decodeIfPresent(GitHubUser.self, forKey: .user)
        assignees = try c.decodeIfPresent([GitHubUser].self, forKey: .assignees) ?? []
        htmlUrl = try c.decodeIfPresent(String.self, forKey: .htmlUrl)
        repositoryUrl = try c.decodeIfPresent(String.self, forKey: .repositoryUrl)
        pullRequest = try c.decodeIfPresent(GitHubPullMarker.self, forKey: .pullRequest)
        comments = try c.decodeIfPresent(Int.self, forKey: .comments)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    /// A PR is an issue with a `pull_request` block.
    var isPullRequest: Bool { pullRequest != nil }
}

/// A branch ref on a PR (`head`/`base`): the branch name and (for `base`) the owning repository.
struct GitHubRef: Decodable, Equatable {
    var ref: String?
    var repo: GitHubRepo?
    init(ref: String? = nil, repo: GitHubRepo? = nil) { self.ref = ref; self.repo = repo }
}

/// A pull request from `/pulls` or `/pulls/:number` — the richer PR view the issue shape lacks.
struct GitHubPull: Decodable {
    var number: Int
    var title: String?
    var body: String?
    var state: String?          // open | closed
    var draft: Bool
    var merged: Bool?
    var mergedAt: String?
    var mergeableState: String?
    var labels: [GitHubLabel]
    var user: GitHubUser?
    var assignees: [GitHubUser]
    var requestedReviewers: [GitHubUser]
    var head: GitHubRef?
    var base: GitHubRef?
    var htmlUrl: String?
    var comments: Int?
    var createdAt: String?
    var updatedAt: String?
    /// Change size; only the single-PR endpoint sends these.
    var additions: Int?
    var deletions: Int?
    var changedFiles: Int?

    init(number: Int, title: String? = nil, body: String? = nil, state: String? = nil, draft: Bool = false,
         merged: Bool? = nil, mergedAt: String? = nil, mergeableState: String? = nil, labels: [GitHubLabel] = [],
         user: GitHubUser? = nil, assignees: [GitHubUser] = [], requestedReviewers: [GitHubUser] = [],
         head: GitHubRef? = nil, base: GitHubRef? = nil, htmlUrl: String? = nil, comments: Int? = nil,
         createdAt: String? = nil, updatedAt: String? = nil, additions: Int? = nil, deletions: Int? = nil,
         changedFiles: Int? = nil) {
        self.number = number; self.title = title; self.body = body; self.state = state; self.draft = draft
        self.merged = merged; self.mergedAt = mergedAt; self.mergeableState = mergeableState; self.labels = labels
        self.user = user; self.assignees = assignees; self.requestedReviewers = requestedReviewers
        self.head = head; self.base = base; self.htmlUrl = htmlUrl; self.comments = comments
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.additions = additions
        self.deletions = deletions; self.changedFiles = changedFiles
    }

    private enum CodingKeys: String, CodingKey {
        case number, title, body, state, draft, merged, mergedAt, mergeableState, labels, user, assignees
        case requestedReviewers, head, base, htmlUrl, comments, createdAt, updatedAt, additions, deletions, changedFiles
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        number = try c.decode(Int.self, forKey: .number)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        draft = try c.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        merged = try c.decodeIfPresent(Bool.self, forKey: .merged)
        mergedAt = try c.decodeIfPresent(String.self, forKey: .mergedAt)
        mergeableState = try c.decodeIfPresent(String.self, forKey: .mergeableState)
        labels = try c.decodeIfPresent([GitHubLabel].self, forKey: .labels) ?? []
        user = try c.decodeIfPresent(GitHubUser.self, forKey: .user)
        assignees = try c.decodeIfPresent([GitHubUser].self, forKey: .assignees) ?? []
        requestedReviewers = try c.decodeIfPresent([GitHubUser].self, forKey: .requestedReviewers) ?? []
        head = try c.decodeIfPresent(GitHubRef.self, forKey: .head)
        base = try c.decodeIfPresent(GitHubRef.self, forKey: .base)
        htmlUrl = try c.decodeIfPresent(String.self, forKey: .htmlUrl)
        comments = try c.decodeIfPresent(Int.self, forKey: .comments)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        additions = try c.decodeIfPresent(Int.self, forKey: .additions)
        deletions = try c.decodeIfPresent(Int.self, forKey: .deletions)
        changedFiles = try c.decodeIfPresent(Int.self, forKey: .changedFiles)
    }

    /// Merged when the flag is set or a merge timestamp is present (`state` stays `closed` for both merged and
    /// abandoned PRs).
    var isMerged: Bool { merged == true || !(mergedAt ?? "").isEmpty }
}

/// A comment from `…/issues/:number/comments` (the same endpoint serves issues and PRs).
struct GitHubComment: Decodable, Equatable {
    var id: Int
    var body: String?
    var user: GitHubUser?
    var createdAt: String?
    init(id: Int, body: String? = nil, user: GitHubUser? = nil, createdAt: String? = nil) {
        self.id = id; self.body = body; self.user = user; self.createdAt = createdAt
    }
}

/// An event from `…/issues/:number/events` — the activity timeline; `event` is the verb.
struct GitHubEvent: Decodable, Equatable {
    var id: Int
    var event: String?
    var actor: GitHubUser?
    var createdAt: String?
    init(id: Int, event: String? = nil, actor: GitHubUser? = nil, createdAt: String? = nil) {
        self.id = id; self.event = event; self.actor = actor; self.createdAt = createdAt
    }
}

/// `GET …/pulls/:number/commits` row (the Dart client kept raw maps; typed here).
struct GitHubCommitRow: Decodable, Equatable {
    struct Author: Decodable, Equatable { var name: String?; var date: String? }
    struct Detail: Decodable, Equatable { var message: String?; var author: Author? }
    var sha: String?
    var commit: Detail?
}

/// `GET …/pulls/:number/files` row.
struct GitHubFileRow: Decodable, Equatable {
    var filename: String?
    var additions: Int?
    var deletions: Int?
    var status: String?
    var patch: String?
}

/// `GET /search/issues` envelope.
struct GitHubSearchResult<T: Decodable>: Decodable { var items: [T]? }
