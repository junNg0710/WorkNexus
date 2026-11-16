import Foundation

/// Ported from: lib/features/notifications/domain/repositories/notification_repository.dart
/// ZenTao web notifications. Local-first: `watchAll` reads the stored list, `refresh` replaces an account's list
/// with the server's; the commands change the store first and then the server.
public protocol ZenTaoNotificationRepository: Sendable {
    func watchAll() -> AsyncStream<[ZenTaoNotification]>
    /// Realnames of the connected ZenTao accounts (from their stored profiles), keyed by accountId.
    func watchAccountRealnames() -> AsyncStream<[String: String]>
    func refresh(accountId: String) async -> Outcome<Void>
    /// Marks one notification (`id`) or, with nil, all of the account's read.
    func markRead(accountId: String, id: String?) async -> Outcome<Void>
    func markUnread(accountId: String, id: String) async -> Outcome<Void>
    func delete(accountId: String, id: String) async -> Outcome<Void>
    func deleteRead(accountId: String) async -> Outcome<Void>
}

/// Ported from: lib/features/workspace_overview/domain/repositories/dashboard_repository.dart
public extension ZenTaoNotificationRepository {
    func watchAccountRealnames() -> AsyncStream<[String: String]> { AsyncStream { $0.yield([:]); $0.finish() } }
}

public protocol ZenTaoDashboardRepository: Sendable {
    func watch(accountId: String) -> AsyncStream<ZenTaoDashboard?>
    func cached(accountId: String) async -> ZenTaoDashboard?
    func refresh(accountId: String) async -> Outcome<Void>
    func syncAssignedWork(accountId: String) async -> Outcome<Void>
}

/// Ported from: lib/features/ticket_editor/domain/{entities/saved_ticket_draft,repositories/ticket_draft_repository}.dart
/// A new bug or task not yet saved to ZenTao, kept so it can be picked up again. Added files are not kept.
public struct ZenTaoSavedDraft: Hashable, Sendable, Identifiable {
    public enum Content: Hashable, Sendable { case bug(BugDraft), task(TaskDraft) }
    public var id: String
    public var accountId: String
    /// The form session the images pasted into the steps were uploaded under.
    public var uid: String
    public var updatedAt: Date
    public var content: Content
    public init(id: String, accountId: String, uid: String, updatedAt: Date, content: Content) {
        self.id = id; self.accountId = accountId; self.uid = uid; self.updatedAt = updatedAt; self.content = content
    }
    /// What the draft is called so far; empty until a title is written.
    public var title: String {
        switch content { case .bug(let d): d.title; case .task(let d): d.name }
    }
}

public protocol ZenTaoTicketDraftRepository: Sendable {
    func watchAll() -> AsyncStream<[ZenTaoSavedDraft]>
    func read(id: String) async -> Outcome<ZenTaoSavedDraft?>
    func save(_ draft: ZenTaoSavedDraft) async -> Outcome<Void>
    func delete(id: String) async -> Outcome<Void>
}
