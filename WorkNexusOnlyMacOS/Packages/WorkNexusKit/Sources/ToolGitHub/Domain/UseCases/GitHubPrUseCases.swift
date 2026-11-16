import CoreDomain

/// Ported from: lib/tools/github/domain/usecases/{close,reopen,merge,update_branch,post_comment}_github_*.dart
/// Each use case does one job and delegates one command to the service (a small, tight group of types, so they
/// share a file — rule 9.2).
public struct PostGitHubComment: Sendable {
    let service: GitHubPrService
    public init(_ service: GitHubPrService) { self.service = service }
    public func callAsFunction(_ ticket: Ticket, body: String) async -> Outcome<Void> { await service.postComment(ticket, body: body) }
}

public struct CloseGitHubItem: Sendable {
    let service: GitHubPrService
    public init(_ service: GitHubPrService) { self.service = service }
    public func callAsFunction(_ ticket: Ticket) async -> Outcome<Void> { await service.closeGitHubItem(ticket) }
}

public struct ReopenGitHubItem: Sendable {
    let service: GitHubPrService
    public init(_ service: GitHubPrService) { self.service = service }
    public func callAsFunction(_ ticket: Ticket) async -> Outcome<Void> { await service.reopenGitHubItem(ticket) }
}

public struct MergeGitHubPr: Sendable {
    let service: GitHubPrService
    public init(_ service: GitHubPrService) { self.service = service }
    public func callAsFunction(_ ticket: Ticket) async -> Outcome<Void> { await service.mergeGitHubPr(ticket) }
}

public struct UpdateGitHubPrBranch: Sendable {
    let service: GitHubPrService
    public init(_ service: GitHubPrService) { self.service = service }
    public func callAsFunction(_ ticket: Ticket) async -> Outcome<Void> { await service.updateGitHubPrBranch(ticket) }
}
