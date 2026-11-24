import CoreDomain
import Foundation
import Observation

/// Ported from: lib/core/navigation/app_nav_controller.dart — the only thing that mutates `AppNavState`, so what must close
/// when something opens is decided here rather than by each caller.
@MainActor @Observable
public final class AppNavController {
    /// The whole state. Reading it follows every change of it: a view kept alive behind the place on screen reads the
    /// part it shows instead (`rail`, `locations`, `ticketHistories`, `toolAccountId`), or it would be drawn again on
    /// every trip between places — every card of a board was.
    public private(set) var state: AppNavState {
        get { access(keyPath: \.state); return store }
        set { apply(newValue) }
    }
    public var rail: RailTarget { access(keyPath: \.rail); return store.rail }
    public var locations: [String: ToolLocation] { access(keyPath: \.locations); return store.locations }
    public var ticketHistories: [String: [String]] { access(keyPath: \.ticketHistories); return store.ticketHistories }
    /// The account whose place is on the rail — or was last, while the rail is on the chat, the dashboard or Settings.
    /// What an account's kept place shows hangs on this, not on `rail`, so it stays as it is behind those.
    public var toolAccountId: String? { access(keyPath: \.toolAccountId); return lastAccount }

    @ObservationIgnored private var store = AppNavState()
    @ObservationIgnored private var lastAccount: String?
    /// The scope of each section asked about (`scope(of:accountId:)`), each observed on its own.
    @ObservationIgnored private var sectionScopes: [String: NavSectionScope] = [:]

    /// The scope of one section of an account (`ToolLocation.scope(of:)`), read again only when that scope changes — not
    /// when the account goes to another section, as `locations` is.
    public func scope(of section: SectionID, accountId: String) -> String? {
        let key = Self.paneKey(accountId, section)
        if let known = sectionScopes[key] { return known.scopeId }
        let scope = NavSectionScope(accountId: accountId, section: section, scopeId: store.locations[accountId]?.scope(of: section))
        sectionScopes[key] = scope
        return scope.scopeId
    }
    /// The navigation panes the reader folded away (`paneKey`), kept for the session so a pane stays folded across a trip to
    /// another place. Dart `collapsedPanesProvider`.
    public private(set) var collapsedPanes: Set<String> = []
    /// The order of the cards in each Kanban column, picked from a board's toolbar: kept for the session and shared by
    /// every board. Dart `boardSortProvider`.
    public private(set) var boardSort = TicketSort.boardDefault
    private let defaultSection: (String) -> SectionID
    /// What the notifications panel (its state lives in FeatureNotifications, not here) must do when something takes the
    /// whole area beside the rail: the editor and a mini app close it (Dart `notificationsOpen: false`). Set by the host.
    @ObservationIgnored public var closeNotifications: (() -> Void)?

    /// - Parameter defaultSection: maps an accountId to the tool's default section (from the `ToolRegistry`).
    public init(defaultSection: @escaping (String) -> SectionID) { self.defaultSection = defaultSection }

    /// Stores `new`, telling the observers of each part that changed (and of the whole).
    private func apply(_ new: AppNavState) {
        let old = store
        guard new != old else { return }
        var account = lastAccount
        if case .account(let id) = new.rail { account = id }
        changing(\.state) {
            changing(\.rail, if: new.rail != old.rail) {
                changing(\.locations, if: new.locations != old.locations) {
                    changing(\.ticketHistories, if: new.ticketHistories != old.ticketHistories) {
                        changing(\.toolAccountId, if: account != lastAccount) { store = new; lastAccount = account }
                    }
                }
            }
        }
        guard new.locations != old.locations else { return }
        for scope in sectionScopes.values {
            let now = new.locations[scope.accountId]?.scope(of: scope.section)
            if scope.scopeId != now { scope.scopeId = now }
        }
    }

    private func changing<T>(_ part: KeyPath<AppNavController, T>, if changed: Bool = true, _ body: () -> Void) {
        if changed { withMutation(keyPath: part, body) } else { body() }
    }

    private func forgetToolAccount(_ gone: (String) -> Bool) {
        guard let id = lastAccount, gone(id) else { return }
        withMutation(keyPath: \.toolAccountId) { lastAccount = nil }
    }

    // MARK: places

    /// Goes to a rail place. Leaving for a place from the rail also leaves the editor and the mini app, which cover the whole
    /// area beside the rail (or the click would look dead).
    public func select(_ rail: RailTarget) {
        if rail != state.rail { PerformanceLog.beginInteraction("open \(rail.key)") }
        state.rail = rail; state.editor = nil; state.miniAppId = nil
        state.userSelectedWorkspace = rail == .workspace
        if case .account(let id) = rail, state.locations[id] == nil {
            state.locations[id] = ToolLocation(section: defaultSection(id))
        }
    }

    /// The first account (provider order) when nothing the user picked is showing: at launch, and after the workspace or the
    /// open account changed under the shell. Never takes away the dashboard the user chose, the chat, Settings, or an account
    /// that still exists (`force` does, for a workspace switch). Dart `selectDefaultAppIfApplicable`.
    public func selectDefaultAppIfApplicable(accounts: [Account], force: Bool = false) {
        guard let first = Account.sort(accounts).first else { return }
        if !force {
            if state.userSelectedWorkspace || state.editor != nil || state.miniAppId != nil { return }
            switch state.rail {
            case .chat, .settings: return
            case .account(let id) where accounts.contains { $0.id == id }: return
            default: break
            }
        }
        select(.account(first.id))
        state.userSelectedWorkspace = false
        if force { state.locations[first.id] = ToolLocation(section: defaultSection(first.id)) }
    }

    /// The user switched workspace: the new one's first account opens, or its dashboard when it has none. Dart
    /// `onWorkspaceSwitched`.
    public func onWorkspaceSwitched(newAccounts: [Account]) {
        state.ticketHistories = [:]
        forgetToolAccount { id in !newAccounts.contains { $0.id == id } }
        if newAccounts.isEmpty {
            state.rail = .workspace; state.workspaceSection = "overview"; state.editor = nil; state.miniAppId = nil
            // Counts as choosing the workspace: until the new (empty) account list arrives, the default selection must not
            // pick an account of the workspace being left.
            state.userSelectedWorkspace = true
        } else {
            state.userSelectedWorkspace = false
            selectDefaultAppIfApplicable(accounts: newAccounts, force: true)
        }
    }

    /// An account went away (or left the workspace): back to the dashboard when it was open. Dart `onAccountRemoved`.
    public func onAccountRemoved(_ id: String) {
        state.locations[id] = nil
        state.ticketHistories[RailTarget.account(id).key] = nil
        if state.rail == .account(id) { state.rail = .workspace; state.workspaceSection = "overview" }
        forgetToolAccount { $0 == id }
    }

    public func location(for accountId: String) -> ToolLocation {
        locations[accountId] ?? ToolLocation(section: defaultSection(accountId))
    }
    /// Goes to `section`, on the scope it was last left on (none the first time). The section on screen stays as it is.
    public func setSection(_ section: SectionID, accountId: String) {
        var l = location(for: accountId)
        guard l.section != section else { return }
        PerformanceLog.beginInteraction("open \(section.rawValue)")
        if let scope = l.scopeId { l.sectionScopes[l.section] = scope } else { l.sectionScopes[l.section] = nil }
        l.section = section; l.scopeId = l.sectionScopes[section]
        state.locations[accountId] = l
    }
    public func setScope(_ scopeId: String?, accountId: String) {
        if scopeId != location(for: accountId).scopeId { PerformanceLog.beginInteraction("open scope \(scopeId ?? "all")") }
        var l = location(for: accountId); l.scopeId = scopeId
        if let scopeId { l.recentScopeIds.removeAll { $0 == scopeId }; l.recentScopeIds.append(scopeId); l.recentScopeIds = Array(l.recentScopeIds.suffix(8)) }
        state.locations[accountId] = l
    }
    public func setQuickScope(_ q: QuickScope, accountId: String) {
        var l = location(for: accountId); l.quickScope = q; state.locations[accountId] = l
    }
    public func setViewMode(_ mode: ViewModeID, section: SectionID, accountId: String) {
        PerformanceLog.beginInteraction("switch to \(mode.rawValue) view")
        var l = location(for: accountId); l.viewModes[section] = mode; state.locations[accountId] = l
    }
    public func setWorkspaceSection(_ id: String) {
        PerformanceLog.beginInteraction("open workspace \(id)")
        state.workspaceSection = id; state.rail = .workspace; state.userSelectedWorkspace = true
        state.editor = nil; state.miniAppId = nil
    }
    public func setSettingsSection(_ id: String) { PerformanceLog.beginInteraction("open settings \(id)"); state.settingsSection = id }

    // MARK: ticket detail (one slide-over history per place)

    /// Shows ticket `id` in the detail slide-over of the place on screen. Opened from the detail itself (a parent / subtask
    /// or a linked ticket) it goes on top of the history, so `goBackTicket` returns to the one it came from.
    public func openTicket(_ id: String) {
        PerformanceLog.beginInteraction("open ticket")
        let k = state.rail.key
        var h = state.ticketHistories[k] ?? []
        h.removeAll { $0 == id }; h.append(id)
        state.ticketHistories[k] = h
    }

    /// Closes the slide-over of the place on screen and forgets its history; the other places keep theirs. Dart `closeTicket`.
    public func closeTicket() { state.ticketHistories[state.rail.key] = nil }

    /// Closes the slide-over on every place (switching workspaces). Dart `closeAllTickets`.
    public func closeAllTickets() { state.ticketHistories = [:] }

    /// Returns the slide-over to the ticket it was opened from; no-op on the first one. Dart `back`.
    public func goBackTicket() {
        let k = state.rail.key
        guard var h = state.ticketHistories[k], h.count > 1 else { return }
        h.removeLast(); state.ticketHistories[k] = h
    }
    public var canGoBackTicket: Bool { (ticketHistories[rail.key]?.count ?? 0) > 1 }
    public var openTicketId: String? { ticketHistories[rail.key]?.last }
    /// The ticket open at `place`, whether or not it is the place on screen (a kept place marks its own).
    public func openTicketId(at place: RailTarget) -> String? { ticketHistories[place.key]?.last }
    /// The ticket open at the tool account's place (`toolAccountId`): the one a board marks.
    public var toolOpenTicketId: String? { toolAccountId.flatMap { openTicketId(at: .account($0)) } }

    // MARK: collapsible panes

    /// The key of an account's place for `collapsedPanes` (the format ToolZenTao's `ZentaoDocsState.paneKey` uses too).
    public static func paneKey(_ accountId: String, _ section: SectionID) -> String { "\(accountId)|\(section.rawValue)" }

    public func isPaneCollapsed(_ key: String) -> Bool { collapsedPanes.contains(key) }
    public func setPane(_ key: String, collapsed: Bool) {
        if collapsed { collapsedPanes.insert(key) } else { collapsedPanes.remove(key) }
    }

    // MARK: board card order

    /// Picking the current field flips its direction; another field starts in its own default direction.
    public func sortBoardCards(by field: TicketSortField) { boardSort = boardSort.toggled(field) }

    // MARK: overlays

    /// Opens the bug / task editor over the whole area beside the rail, so the notifications panel closes.
    /// `prefill` is what a new ticket starts with (one made from a chat message); every other opening clears it.
    public func openEditor(_ route: TicketEditorRoute, prefill: TicketEditorPrefill? = nil) {
        state.editor = route; state.editorPrefill = prefill; closeNotifications?()
    }
    public func closeEditor() { state.editor = nil; state.editorPrefill = nil }

    /// Shows a mini app beside the rail (nil: back to the rail's place). Like Dart `showMiniApp` it also drops what covers
    /// it: the editor, the notifications panel and every open ticket.
    public func openMiniApp(_ id: String?) {
        state.miniAppId = id
        if id != nil { state.editor = nil; state.ticketHistories = [:]; closeNotifications?() }
    }
}

/// One section's scope, observed on its own (`AppNavController.scope(of:accountId:)`).
@MainActor @Observable
final class NavSectionScope {
    let accountId: String
    let section: SectionID
    var scopeId: String?
    init(accountId: String, section: SectionID, scopeId: String?) { self.accountId = accountId; self.section = section; self.scopeId = scopeId }
}
