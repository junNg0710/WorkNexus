import CoreDomain
import Foundation

/// Ported from: lib/shared/board/presentation/providers/filter_providers.dart (`FilterController`, `boardKeyProvider`)
public extension BoardController {
    /// `section|accountId|scopeId` of the place on screen: each board remembers its own filter.
    var currentBoardKey: String {
        let s = nav.state
        guard case .account(let accountId) = s.rail, let loc = s.locations[accountId] else { return "default" }
        return "\(loc.section.rawValue)|\(accountId)|\(loc.scopeId ?? "")"
    }

    private func toggled<T: Hashable>(_ set: Set<T>, _ v: T) -> Set<T> {
        var n = set
        if n.contains(v) { n.remove(v) } else { n.insert(v) }
        return n
    }

    /// The statuses a ZenTao task board opens on: the work still to do. Done, closed and cancelled tasks are one click
    /// away in Filters (not in the Flutter app, which opens on every status).
    static let openTaskStatuses: Set<String> = [BoardZenTaoTaskColumn.notStarted, .inProgress, .paused].reduce(into: []) { $0.insert($1.rawValue) }
    /// The statuses a ZenTao bug board opens on: the bugs still to be fixed (new and confirmed); resolved, postponed,
    /// non-fix and closed bugs are one click away in Filters.
    static let openBugStatuses: Set<String> = [BoardZenTaoBugColumn.newUnconfirmed, .confirmedToFix].reduce(into: []) { $0.insert($1.rawValue) }

    /// The filter a board starts with the first time it is opened in a session (after that it is the one it was left with).
    private func initial(for key: String, current: FilterState? = nil) -> FilterState {
        var base = current.map(cleared) ?? FilterState()
        if key.hasPrefix("zentao.") { base.savedView = .all }
        if key.hasPrefix("zentao.tasks|") { base.zentaoStatuses = Self.openTaskStatuses }
        if key.hasPrefix("zentao.bugs|") { base.zentaoStatuses = Self.openBugStatuses }
        return base
    }

    private func cleared(_ from: FilterState) -> FilterState {
        var f = from
        f.providers = []; f.accountIds = []; f.projectIds = []; f.statuses = []; f.priorities = []; f.severities = []
        f.assignees = []; f.reviewers = []; f.bugTypes = []; f.resolutions = []; f.zentaoStatuses = []
        f.resolvers = []; f.reporters = []; f.confirmations = []; f.modules = []; f.search = ""
        return f
    }

    func setWorkspace(_ id: String) {
        filter.workspaceId = id; filter.accountIds = []; filter.projectIds = []
        pulse()
    }
    func setSavedView(_ v: SavedView) { filter.savedView = v }
    func setSearch(_ q: String) { filter.search = q }
    func toggleProvider(_ p: ProviderType) { filter.providers = toggled(filter.providers, p) }
    func toggleAccount(_ id: String) { filter.accountIds = toggled(filter.accountIds, id) }
    func toggleProject(_ id: String) { filter.projectIds = toggled(filter.projectIds, id) }
    func toggleStatus(_ s: UnifiedStatus) { filter.statuses = toggled(filter.statuses, s) }
    func togglePriority(_ p: Priority) { filter.priorities = toggled(filter.priorities, p) }
    func toggleSeverity(_ s: Int) { filter.severities = toggled(filter.severities, s) }
    func toggleAssignee(_ a: String) { filter.assignees = toggled(filter.assignees, a) }
    func toggleReviewer(_ r: String) { filter.reviewers = toggled(filter.reviewers, r) }
    func toggleBugType(_ t: String) { filter.bugTypes = toggled(filter.bugTypes, t) }
    func toggleResolution(_ r: String) { filter.resolutions = toggled(filter.resolutions, r) }
    func toggleZenTaoStatus(_ s: String) { filter.zentaoStatuses = toggled(filter.zentaoStatuses, s) }
    func toggleResolver(_ r: String) { filter.resolvers = toggled(filter.resolvers, r) }
    func toggleReporter(_ r: String) { filter.reporters = toggled(filter.reporters, r) }
    func toggleConfirmation(_ c: String) { filter.confirmations = toggled(filter.confirmations, c) }
    func toggleModule(_ id: String) { filter.modules = toggled(filter.modules, id) }
    /// Single-select a module (nil clears) — the module tree beside a ZenTao bug list.
    func selectModule(_ id: String?) { filter.modules = id.map { [$0] } ?? [] }

    func clearFacet(_ kind: BoardFacetKind) {
        switch kind {
        case .status: filter.zentaoStatuses = []
        case .assignee: filter.assignees = []
        case .resolvedBy: filter.resolvers = []
        case .openedBy: filter.reporters = []
        case .confirmed: filter.confirmations = []
        case .reviewer: filter.reviewers = []
        case .severity: filter.severities = []
        case .priority: filter.priorities = []
        case .bugType: filter.bugTypes = []
        case .resolution: filter.resolutions = []
        case .module: filter.modules = []
        }
    }

    func clearAll() { filter = cleared(filter) }

    /// A built-in view that owns the board (e.g. "Assigned to me"): sets the current filter aside and shows only that view.
    func enterOwnView(_ view: SavedView) {
        if let key = activeKey, setAside[key] == nil { setAside[key] = filter }
        var f = cleared(filter); f.modules = filter.modules; f.savedView = view
        filter = f
    }

    func leaveOwnView() {
        let aside = activeKey.flatMap { setAside.removeValue(forKey: $0) }
        var f = aside ?? filter
        f.workspaceId = filter.workspaceId; f.modules = filter.modules; f.savedView = .all
        filter = f
    }

    /// Switching boards: remembers the filter of the one left and restores the one entered.
    func openBoard(_ key: String) {
        let next = SwitchBoardFilter()(memory: memory, fromKey: activeKey, toKey: key, current: filter,
                                       initial: initial(for: key, current: filter))
        memory = next.memory
        if activeKey != key { clearSelection() }
        activeKey = key
        var f = next.filter; f.workspaceId = filter.workspaceId
        filter = f
    }

    func applyPreset(_ preset: FilterState) {
        var f = preset
        f.workspaceId = filter.workspaceId
        if preset.savedView == .all { f.savedView = filter.savedView }
        filter = f
    }

    // MARK: Saved presets

    /// Saves the current filter under `name` (an existing name is overwritten).
    func saveCurrentFilter(named name: String) async -> Outcome<Void> {
        guard let preset = BuildSavedFilter()(name: name, filter: filter, existing: savedFilters, now: Date()) else { return .success(()) }
        return await savedFilterRepo.upsert(preset)
    }
    func deleteSavedFilter(_ id: String) async -> Outcome<Void> { await savedFilterRepo.delete(id: id) }
    func apply(_ preset: SavedFilter) { applyPreset(preset.filter) }
}
