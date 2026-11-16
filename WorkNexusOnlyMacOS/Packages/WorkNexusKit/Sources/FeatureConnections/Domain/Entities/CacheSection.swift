/// Ported from: lib/features/connections/domain/entities/cache_section.dart
/// A group of locally cached, server-synced data that can be cleared on its own. Accounts, workspaces, settings,
/// saved filters and chat sign-ins are never part of the cache.
public enum CacheSection: CaseIterable, Hashable, Sendable {
    /// Tickets, their comments and activity, and the projects they belong to.
    case tickets
    /// The dashboard snapshot, ZenTao notifications and profiles.
    case dashboard
    /// Chat conversations, messages and contacts.
    case chat
    /// Saved translations of tickets and chat messages.
    case translations
}
