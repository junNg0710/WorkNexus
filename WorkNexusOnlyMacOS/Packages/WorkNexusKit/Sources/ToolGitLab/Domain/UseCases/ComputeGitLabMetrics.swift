import CoreDomain

/// Ported from: lib/tools/gitlab/domain/usecases/compute_gitlab_metrics.dart
/// Primary: cached project count. Secondary: open merge requests. Plain counts — the presentation layer attaches
/// the localized labels (`ToolMetrics` lives in `CoreTools`, which the domain layer must not import).
public struct GitLabMetrics: Sendable, Equatable {
    public let primaryCount: Int
    public let secondaryCount: Int
}

public struct ComputeGitLabMetrics: Sendable {
    public init() {}

    public func callAsFunction(tickets: [Ticket], projectCount: Int, accountId: String) -> GitLabMetrics {
        var openMrs = 0
        for t in tickets {
            guard t.accountId == accountId, t.providerType == .gitlab, t.status != .done else { continue }
            if (t.externalType ?? "").lowercased() == "mergerequest" { openMrs += 1 }
        }
        return GitLabMetrics(primaryCount: projectCount, secondaryCount: openMrs)
    }
}
