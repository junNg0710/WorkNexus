import CoreDomain
import Foundation

/// Ported from: lib/shared/sync/data/{ticket_store,source_list_cache}.dart (the persistence seams).
/// SharedKit cannot import GRDB / CorePersistence, so the pieces of the sync layer that need more than the
/// `CoreDomain` repositories expose are ports the composition root can implement over the database.

/// Writes that the plain repositories cannot express (replace-by-ticket, unconditional overwrite).
/// `RepositoryDetailWriter` is the default built on `CoreDomain` repositories.
public protocol DetailWriting: Sendable {
    /// Replaces the provider's comments on `ticketId` with `comments` (the user's internal notes stay).
    func replaceProviderComments(ticketId: String, comments: [Comment]) async -> Outcome<Void>
    /// Replaces the activity of `ticketId` with `events`.
    func replaceActivity(ticketId: String, events: [ActivityEvent]) async -> Outcome<Void>
    /// Overwrites the stored row of `ticket` even when its `sourceHash` is unchanged (optimistic update / rollback).
    func overwrite(ticket: Ticket) async -> Outcome<Void>
    /// Replaces the provider's comments and / or the activity of `ticketId` in ONE write (nil leaves that list alone), so a
    /// watcher never sees the new comments next to the old activity. A database-backed writer does it in a transaction.
    func replaceDetail(ticketId: String, comments: [Comment]?, events: [ActivityEvent]?) async -> Outcome<Void>
}

public extension DetailWriting {
    /// Two writes, one after the other (writers without a transaction of their own).
    func replaceDetail(ticketId: String, comments: [Comment]?, events: [ActivityEvent]?) async -> Outcome<Void> {
        if let comments, case .failure(let f) = await replaceProviderComments(ticketId: ticketId, comments: comments) { return .failure(f) }
        if let events { return await replaceActivity(ticketId: ticketId, events: events) }
        return .success(())
    }
}

/// Persists the last-fetched provider container lists so the sidebar tree can paint from disk on launch.
/// `kind` is `"products"` or `"projects"`; `json` is an opaque payload owned by `SourceListCache`.
public protocol SourceListSnapshotStore: Sendable {
    func read(accountId: String, kind: String) async -> String?
    func write(accountId: String, kind: String, json: String) async
}

/// Process-memory `SourceListSnapshotStore` (default; a database-backed one survives launches).
public actor InMemorySourceListSnapshotStore: SourceListSnapshotStore {
    private var items: [String: String] = [:]
    public init() {}
    public func read(accountId: String, kind: String) -> String? { items["\(accountId)|\(kind)"] }
    public func write(accountId: String, kind: String, json: String) { items["\(accountId)|\(kind)"] = json }
}

/// Optional provider-specific behaviours the shared coordinator cannot know (GitLab/GitHub reviewers, member lists,
/// raw clients). Tool modules register these closures; each receives the pooled adapter and downcasts it.
public struct SyncExtensions: Sendable {
    public var setReviewers: (@Sendable (ProviderAdapter, Ticket, [String]) async -> Outcome<Void>?)?
    public var listUsers: (@Sendable (ProviderAdapter, Ticket) async -> Outcome<[ProviderUser]>?)?
    public init(setReviewers: (@Sendable (ProviderAdapter, Ticket, [String]) async -> Outcome<Void>?)? = nil,
                listUsers: (@Sendable (ProviderAdapter, Ticket) async -> Outcome<[ProviderUser]>?)? = nil) {
        self.setReviewers = setReviewers; self.listUsers = listUsers
    }
}
