import CoreDomain
import Foundation
import Observation

/// Ported from: lib/core/navigation/app_nav_controller.dart — the only thing that mutates `AppNavState`, so what must close
/// when something opens is decided here rather than by each caller.
@MainActor @Observable
public final class AppNavController {
    public private(set) var state = AppNavState()
    /// The navigation panes the reader folded away (`paneKey`), kept for the session so a pane stays folded across a trip to
    /// another place. Dart `collapsedPanesProvider`.
    public private(set) var collapsedPanes: Set<String> = []
    private let defaultSection: (String) -> SectionID
    /// What the notifications panel (its state lives in FeatureNotifications, not here) must do when something takes the
    /// whole area beside the rail: the editor and a mini app close it (Dart `notificationsOpen: false`). Set by the host.
    @ObservationIgnored public var closeNotifications: (() -> Void)?

    /// - Parameter defaultSection: maps an accountId to the tool's default section (from the `ToolRegistry`).
    public init(defaultSection: @escaping (String) -> SectionID) { self.defaultSection = defaultSection }

    // MARK: places

    /// Goes to a rail place. Leaving for a place from the rail also leaves the editor and the mini app, which cover the whole
    /// area beside the rail (or the click would look dead).
    public func select(_ rail: RailTarget) {
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
    }

    public func location(for accountId: String) -> ToolLocation {
        state.locations[accountId] ?? ToolLocation(section: defaultSection(accountId))
    }
    public func setSection(_ section: SectionID, accountId: String) {
        var l = location(for: accountId); l.section = section; l.scopeId = nil; state.locations[accountId] = l
    }
    public func setScope(_ scopeId: String?, accountId: String) {
        var l = location(for: accountId); l.scopeId = scopeId
        if let scopeId { l.recentScopeIds.removeAll { $0 == scopeId }; l.recentScopeIds.append(scopeId); l.recentScopeIds = Array(l.recentScopeIds.suffix(8)) }
        state.locations[accountId] = l
    }
    public func setQuickScope(_ q: QuickScope, accountId: String) {
        var l = location(for: accountId); l.quickScope = q; state.locations[accountId] = l
    }
    public func setViewMode(_ mode: ViewModeID, section: SectionID, accountId: String) {
        var l = location(for: accountId); l.viewModes[section] = mode; state.locations[accountId] = l
    }
    public func setWorkspaceSection(_ id: String) {
        state.workspaceSection = id; state.rail = .workspace; state.userSelectedWorkspace = true
        state.editor = nil; state.miniAppId = nil
    }
    public func setSettingsSection(_ id: String) { state.settingsSection = id }

    // MARK: ticket detail (one slide-over history per place)

    /// Shows ticket `id` in the detail slide-over of the place on screen. Opened from the detail itself (a parent / subtask
    /// or a linked ticket) it goes on top of the history, so `goBackTicket` returns to the one it came from.
    public func openTicket(_ id: String) {
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
    public var canGoBackTicket: Bool { (state.ticketHistories[state.rail.key]?.count ?? 0) > 1 }
    public var openTicketId: String? { state.ticketHistories[state.rail.key]?.last }

    // MARK: collapsible panes

    /// The key of an account's place for `collapsedPanes` (the format ToolZenTao's `ZentaoDocsState.paneKey` uses too).
    public static func paneKey(_ accountId: String, _ section: SectionID) -> String { "\(accountId)|\(section.rawValue)" }

    public func isPaneCollapsed(_ key: String) -> Bool { collapsedPanes.contains(key) }
    public func setPane(_ key: String, collapsed: Bool) {
        if collapsed { collapsedPanes.insert(key) } else { collapsedPanes.remove(key) }
    }

    // MARK: overlays

    /// Opens the bug / task editor over the whole area beside the rail, so the notifications panel closes.
    public func openEditor(_ route: TicketEditorRoute) { state.editor = route; closeNotifications?() }
    public func closeEditor() { state.editor = nil }

    /// Shows a mini app beside the rail (nil: back to the rail's place). Like Dart `showMiniApp` it also drops what covers
    /// it: the editor, the notifications panel and every open ticket.
    public func openMiniApp(_ id: String?) {
        state.miniAppId = id
        if id != nil { state.editor = nil; state.ticketHistories = [:]; closeNotifications?() }
    }
}
