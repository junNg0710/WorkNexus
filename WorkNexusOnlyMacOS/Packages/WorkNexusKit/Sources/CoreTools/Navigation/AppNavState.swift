import CoreDomain
import Foundation

/// Ported from: lib/core/navigation/app_nav_state.dart
/// Shell hierarchy: Workspace(L1) → Account(L2) → Section(L3) → Scope(L4) → Item(L5).
public enum RailTarget: Hashable, Sendable {
    case workspace
    case account(String)
    case chat
    case settings
}

public enum QuickScope: String, Hashable, Codable, Sendable { case none, assignedToMe, pinned, recent }

public struct ToolLocation: Hashable, Sendable {
    public var section: SectionID
    public var scopeId: String?
    public var quickScope: QuickScope
    public var viewModes: [SectionID: ViewModeID]
    public var recentScopeIds: [String]
    public init(section: SectionID, scopeId: String? = nil, quickScope: QuickScope = .none,
                viewModes: [SectionID: ViewModeID] = [:], recentScopeIds: [String] = []) {
        self.section = section; self.scopeId = scopeId; self.quickScope = quickScope
        self.viewModes = viewModes; self.recentScopeIds = recentScopeIds
    }
}

public enum TicketEditorRoute: Hashable, Sendable {
    /// A new bug in `productId`, optionally a copy of bug `copyOf`, or filed against `executionId` / task `taskId`.
    /// The trailing payload defaults to nil, so `.newBug(accountId:productId:)` keeps compiling.
    case newBug(accountId: String, productId: String? = nil, executionId: String? = nil, copyOf: String? = nil, taskId: String? = nil)
    /// A new task in `executionId`, optionally a copy of task `copyOf` or a subtask of `parentId`.
    case newTask(accountId: String, executionId: String? = nil, copyOf: String? = nil, parentId: String? = nil)
    case editBug(accountId: String, ticketId: String)
    case editTask(accountId: String, ticketId: String)
}

public struct AppNavState: Equatable, Sendable {
    public var rail: RailTarget = .workspace
    public var workspaceSection = "overview"
    public var settingsSection = "general"
    public var locations: [String: ToolLocation] = [:]
    /// Opened tickets per place (key = rail target id), newest last; the last one is the open detail slide-over.
    public var ticketHistories: [String: [String]] = [:]
    public var editor: TicketEditorRoute?
    public var miniAppId: String?
    /// The user picked the workspace pages themselves (rail "Dashboard", a workspace section): the default selection
    /// (first account at launch) must not take the place away from them. Dart `userSelectedWorkspace`.
    public var userSelectedWorkspace = false
    public init() {}
}

public extension RailTarget {
    var key: String {
        switch self { case .workspace: "workspace"; case .account(let id): "account:\(id)"; case .chat: "chat"; case .settings: "settings" }
    }
}
