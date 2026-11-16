import CoreDomain

/// Ported from: lib/tools/gitlab/domain/usecases/{approve,unapprove,close,reopen,merge,rebase,set_draft,post_comment}_gitlab_mr.dart
/// Each use case does one job and delegates one command to the service (a small, tight group of types, so they
/// share a file — rule 9.2).
public struct PostGitLabMrComment: Sendable {
    let service: GitLabMrService
    public init(_ service: GitLabMrService) { self.service = service }
    public func callAsFunction(_ ticket: Ticket, body: String) async -> Outcome<Void> { await service.postComment(ticket, body: body) }
}

public struct CloseGitLabMr: Sendable {
    let service: GitLabMrService
    public init(_ service: GitLabMrService) { self.service = service }
    public func callAsFunction(_ ticket: Ticket) async -> Outcome<Void> { await service.closeGitLabItem(ticket) }
}

public struct ReopenGitLabMr: Sendable {
    let service: GitLabMrService
    public init(_ service: GitLabMrService) { self.service = service }
    public func callAsFunction(_ ticket: Ticket) async -> Outcome<Void> { await service.reopenGitLabItem(ticket) }
}

public struct ApproveGitLabMr: Sendable {
    let service: GitLabMrService
    public init(_ service: GitLabMrService) { self.service = service }
    public func callAsFunction(_ ticket: Ticket) async -> Outcome<Void> { await service.approveGitLabMr(ticket) }
}

public struct UnapproveGitLabMr: Sendable {
    let service: GitLabMrService
    public init(_ service: GitLabMrService) { self.service = service }
    public func callAsFunction(_ ticket: Ticket) async -> Outcome<Void> { await service.unapproveGitLabMr(ticket) }
}

public struct RebaseGitLabMr: Sendable {
    let service: GitLabMrService
    public init(_ service: GitLabMrService) { self.service = service }
    public func callAsFunction(_ ticket: Ticket) async -> Outcome<Void> { await service.rebaseGitLabMr(ticket) }
}

public struct MergeGitLabMr: Sendable {
    let service: GitLabMrService
    public init(_ service: GitLabMrService) { self.service = service }
    /// Merges `ticket`; a nil option keeps the MR's own setting.
    public func callAsFunction(_ ticket: Ticket, squash: Bool? = nil, removeSourceBranch: Bool? = nil) async -> Outcome<Void> {
        await service.mergeGitLabMr(ticket, squash: squash, removeSourceBranch: removeSourceBranch)
    }
}

/// Marks a merge request as a draft, or as ready for review.
public struct SetGitLabMrDraft: Sendable {
    let service: GitLabMrService
    public init(_ service: GitLabMrService) { self.service = service }
    public func callAsFunction(_ ticket: Ticket, draft: Bool) async -> Outcome<Void> { await service.setGitLabMrDraft(ticket, draft: draft) }
}
