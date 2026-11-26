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
    /// The scope each section was last left on (Tasks its execution, Bugs its product): going back to a section finds it
    /// where it was, instead of re-picking a scope and reading the board again.
    public var sectionScopes: [SectionID: String]
    public init(section: SectionID, scopeId: String? = nil, quickScope: QuickScope = .none,
                viewModes: [SectionID: ViewModeID] = [:], recentScopeIds: [String] = [], sectionScopes: [SectionID: String] = [:]) {
        self.section = section; self.scopeId = scopeId; self.quickScope = quickScope
        self.viewModes = viewModes; self.recentScopeIds = recentScopeIds; self.sectionScopes = sectionScopes
    }

    /// The scope of `section`: the open one while it is the section on screen, else the one it was left on. What a
    /// section kept alive behind another one shows hangs on this, so it stays as it is until it is back.
    public func scope(of section: SectionID) -> String? { section == self.section ? scopeId : sectionScopes[section] }
}

public enum TicketEditorRoute: Hashable, Sendable {
    /// A new bug in `productId`, optionally a copy of bug `copyOf`, or filed against `executionId` / task `taskId`.
    /// The trailing payload defaults to nil, so `.newBug(accountId:productId:)` keeps compiling.
    case newBug(accountId: String, productId: String? = nil, executionId: String? = nil, copyOf: String? = nil, taskId: String? = nil)
    /// A new task in `executionId`, optionally a copy of task `copyOf`, a subtask of `parentId`, or made from bug `fromBug`.
    case newTask(accountId: String, executionId: String? = nil, copyOf: String? = nil, parentId: String? = nil, fromBug: String? = nil)
    case editBug(accountId: String, ticketId: String)
    case editTask(accountId: String, ticketId: String)
}

/// What a new bug or task opens filled in with (a ticket made from a chat message): its title and its body as HTML,
/// and the pictures the body shows - each stands in `bodyHtml` as its `token` until the editor has uploaded it.
public struct TicketEditorPrefill: Hashable, Sendable {
    public struct Picture: Hashable, Sendable {
        public var token: String
        public var name: String
        public var data: Data
        public init(token: String, name: String, data: Data) { self.token = token; self.name = name; self.data = data }

        // By what names it: the navigation state is compared on every change, megabytes of picture are not.
        public static func == (a: Picture, b: Picture) -> Bool { a.token == b.token && a.name == b.name && a.data.count == b.data.count }
        public func hash(into hasher: inout Hasher) { hasher.combine(token); hasher.combine(name); hasher.combine(data.count) }
    }

    public var title: String
    public var bodyHtml: String
    public var pictures: [Picture]
    public init(title: String, bodyHtml: String, pictures: [Picture] = []) {
        self.title = title; self.bodyHtml = bodyHtml; self.pictures = pictures
    }
}

public struct AppNavState: Equatable, Sendable {
    public var rail: RailTarget = .workspace
    public var workspaceSection = "overview"
    public var settingsSection = "general"
    public var locations: [String: ToolLocation] = [:]
    /// Opened tickets per place (key = rail target id), newest last; the last one is the open detail slide-over.
    public var ticketHistories: [String: [String]] = [:]
    public var editor: TicketEditorRoute?
    /// What the open editor's new ticket starts with; nil for an ordinary new ticket. Goes when the editor closes.
    public var editorPrefill: TicketEditorPrefill?
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
