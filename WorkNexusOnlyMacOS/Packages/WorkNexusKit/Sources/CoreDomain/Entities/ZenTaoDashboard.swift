import Foundation

/// Ported from: lib/features/workspace_overview/domain/entities/{zentao_dashboard,dashboard_*}.dart
/// What a ZenTao `GET /user?fields=...` snapshot holds (the account's personal overview). Parsed on read from
/// the raw stored reply by `ZenTaoDashboardMapper`.
public enum ZenTaoDashboardItemKind: String, Sendable, Hashable { case task, bug, story, todo }

public struct ZenTaoDashboardWorkItem: Hashable, Sendable, Identifiable {
    public var kind: ZenTaoDashboardItemKind
    public var id: String
    public var title: String
    public var status: String?
    public var statusLabel: String?
    public var priority: Int?
    public var deadline: Date?
    public var context: String?
    public init(kind: ZenTaoDashboardItemKind, id: String, title: String, status: String? = nil, statusLabel: String? = nil,
                priority: Int? = nil, deadline: Date? = nil, context: String? = nil) {
        self.kind = kind; self.id = id; self.title = title; self.status = status; self.statusLabel = statusLabel
        self.priority = priority; self.deadline = deadline; self.context = context
    }
}

public struct ZenTaoDashboardExecution: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var projectName: String?
    public var status: String?
    public var progress: Double?
    public var end: Date?
    public init(id: String, name: String, projectName: String? = nil, status: String? = nil, progress: Double? = nil, end: Date? = nil) {
        self.id = id; self.name = name; self.projectName = projectName; self.status = status; self.progress = progress; self.end = end
    }
}

public struct ZenTaoDashboardActivity: Hashable, Sendable, Identifiable {
    public var id: String
    public var actor: String
    public var action: String
    public var objectType: String
    public var objectId: String
    public var objectName: String?
    public var date: Date?
    public init(id: String, actor: String, action: String, objectType: String, objectId: String, objectName: String? = nil, date: Date? = nil) {
        self.id = id; self.actor = actor; self.action = action; self.objectType = objectType
        self.objectId = objectId; self.objectName = objectName; self.date = date
    }
}

public struct ZenTaoDashboardProfile: Hashable, Sendable {
    public var account: String
    public var realname: String
    public var role: String?
    public var email: String?
    public var lastLogin: Date?
    public init(account: String, realname: String, role: String? = nil, email: String? = nil, lastLogin: Date? = nil) {
        self.account = account; self.realname = realname; self.role = role; self.email = email; self.lastLogin = lastLogin
    }
}

public struct ZenTaoDashboard: Hashable, Sendable {
    public var accountId: String
    public var profile: ZenTaoDashboardProfile
    public var fetchedAt: Date
    public var tasks: [ZenTaoDashboardWorkItem] = []
    public var taskTotal = 0
    public var bugs: [ZenTaoDashboardWorkItem] = []
    public var bugTotal = 0
    public var stories: [ZenTaoDashboardWorkItem] = []
    public var storyTotal = 0
    public var todos: [ZenTaoDashboardWorkItem] = []
    public var todoTotal = 0
    public var executions: [ZenTaoDashboardExecution] = []
    public var executionTotal = 0
    public var activities: [ZenTaoDashboardActivity] = []
    public var projectTotal: Int?
    public var productTotal: Int?
    public var docTotal: Int?
    public init(accountId: String, profile: ZenTaoDashboardProfile, fetchedAt: Date) {
        self.accountId = accountId; self.profile = profile; self.fetchedAt = fetchedAt
    }
}
