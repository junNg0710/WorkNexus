import CoreDomain

/// Ported from: lib/shared/board/domain/entities/filter_state.dart
/// The full active filter selection driving the board/list. `workspaceId` is `"all"` or a specific workspace.
/// Value equality means derived state recomputes only on real changes.
public struct FilterState: Hashable, Sendable {
    public var workspaceId: String = "all"
    public var savedView: SavedView = .all
    public var providers: Set<ProviderType> = []
    public var accountIds: Set<String> = []
    public var projectIds: Set<String> = []
    public var statuses: Set<UnifiedStatus> = []
    public var priorities: Set<Priority> = []
    public var severities: Set<Int> = []
    public var assignees: Set<String> = []
    public var reviewers: Set<String> = []
    public var bugTypes: Set<String> = []
    public var resolutions: Set<String> = []
    /// ZenTao boards: the board column (status) a ticket sits in.
    public var zentaoStatuses: Set<String> = []
    /// ZenTao boards: who resolved / opened a bug (names).
    public var resolvers: Set<String> = []
    public var reporters: Set<String> = []
    /// ZenTao boards: whether a bug was confirmed (`"1"` / `"0"`).
    public var confirmations: Set<String> = []
    /// ZenTao bug boards: the product modules (ids) a bug sits in.
    public var modules: Set<String> = []
    public var search: String = ""

    public init() {}

    public var hasActiveFilters: Bool {
        !providers.isEmpty || !accountIds.isEmpty || !projectIds.isEmpty || !statuses.isEmpty
            || !priorities.isEmpty || !severities.isEmpty || !assignees.isEmpty || !reviewers.isEmpty
            || !bugTypes.isEmpty || !resolutions.isEmpty || !zentaoStatuses.isEmpty || !resolvers.isEmpty
            || !reporters.isEmpty || !confirmations.isEmpty || !modules.isEmpty
            || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether this filter can hide any of a board's tickets (a paged board then scans further pages).
    public var narrowsTickets: Bool { hasActiveFilters || workspaceId != "all" || savedView != .all }

    /// Number of chip-style filters active (excludes free-text search).
    public var activeTokenCount: Int {
        providers.count + accountIds.count + projectIds.count + statuses.count + priorities.count
            + severities.count + assignees.count + reviewers.count + bugTypes.count + resolutions.count
            + zentaoStatuses.count + resolvers.count + reporters.count + confirmations.count + modules.count
    }
}
