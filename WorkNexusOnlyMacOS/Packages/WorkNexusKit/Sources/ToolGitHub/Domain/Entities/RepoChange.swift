import Foundation

/// Ported from: lib/core/domain/value_objects/repo_change.dart
/// (Not in `CoreDomain` yet; ToolGitLab declares an identical copy — hoist both into the shared kernel when
/// the diff view moves to `SharedKit`.)
/// A single commit on a pull request (view-only detail data).
public struct RepoCommit: Sendable, Hashable, Identifiable {
    public var sha: String
    public var shortSha: String
    public var title: String
    public var author: String?
    public var date: Date?
    public var id: String { sha }
    public init(sha: String, shortSha: String, title: String, author: String? = nil, date: Date? = nil) {
        self.sha = sha; self.shortSha = shortSha; self.title = title; self.author = author; self.date = date
    }
}

/// A single changed file. `additions`/`deletions` are line counts; `status` is added/modified/deleted/renamed;
/// `diff` is the unified-diff hunk text when available (nil/empty for binary or oversized files).
public struct RepoFileChange: Sendable, Hashable, Identifiable {
    public var path: String
    public var additions: Int
    public var deletions: Int
    public var status: String?
    public var diff: String?
    public var id: String { path }
    public init(path: String, additions: Int = 0, deletions: Int = 0, status: String? = nil, diff: String? = nil) {
        self.path = path; self.additions = additions; self.deletions = deletions; self.status = status; self.diff = diff
    }
}

/// Counts additions (+) and deletions (-) in a unified-diff hunk, ignoring the `+++`/`---` file headers.
public func countDiffLines(_ diff: String?) -> (additions: Int, deletions: Int) {
    guard let diff, !diff.isEmpty else { return (0, 0) }
    var adds = 0, dels = 0
    for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { adds += 1 }
        else if line.hasPrefix("-") && !line.hasPrefix("---") { dels += 1 }
    }
    return (adds, dels)
}
