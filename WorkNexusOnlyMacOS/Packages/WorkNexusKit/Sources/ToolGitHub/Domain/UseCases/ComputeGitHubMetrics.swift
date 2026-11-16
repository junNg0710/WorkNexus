import CoreDomain

/// Ported from: lib/tools/github/domain/usecases/compute_github_metrics.dart
/// Primary: open pull requests. Secondary: open issues. Plain counts — the presentation layer attaches the
/// localized labels (`ToolMetrics` lives in `CoreTools`, which the domain layer must not import).
public struct GitHubMetrics: Sendable, Equatable {
    public let primaryCount: Int
    public let secondaryCount: Int
}

public struct ComputeGitHubMetrics: Sendable {
    public init() {}

    public func callAsFunction(tickets: [Ticket], accountId: String) -> GitHubMetrics {
        var openPulls = 0, openIssues = 0
        for t in tickets {
            guard t.accountId == accountId, t.providerType == .github, t.status != .done else { continue }
            if (t.externalType ?? "").lowercased() == "pullrequest" { openPulls += 1 } else { openIssues += 1 }
        }
        return GitHubMetrics(primaryCount: openPulls, secondaryCount: openIssues)
    }
}
