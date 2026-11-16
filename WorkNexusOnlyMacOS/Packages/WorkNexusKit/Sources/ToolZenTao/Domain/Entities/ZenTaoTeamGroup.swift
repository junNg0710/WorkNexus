import Foundation

/// One person of a team group: the ZenTao login and the name they go by (kept, so the group reads without the user list).
public struct ZenTaoTeamMember: Hashable, Sendable, Codable, Identifiable {
    public var login: String
    public var name: String
    public var id: String { login }
    public init(login: String, name: String) { self.login = login; self.name = name }
}

/// A set of people a team leader follows across executions and products, saved on this Mac. Not in the Flutter app.
public struct ZenTaoTeamGroup: Hashable, Sendable, Identifiable {
    public var id: String
    public var accountId: String
    public var name: String
    public var members: [ZenTaoTeamMember]
    public var createdAt: Date
    public init(id: String = UUID().uuidString, accountId: String, name: String, members: [ZenTaoTeamMember], createdAt: Date = Date()) {
        self.id = id; self.accountId = accountId; self.name = name; self.members = members; self.createdAt = createdAt
    }
}

/// What was read of one person's assigned work across every execution (tasks) or product (bugs).
public struct ZenTaoPersonWork: Equatable, Sendable {
    /// Local ticket ids, newest first.
    public var ids: [String]
    /// How many tickets ZenTao holds for them.
    public var total: Int
    /// Whether reading stopped at the cap with more left.
    public var truncated: Bool
    public init(ids: [String], total: Int, truncated: Bool) { self.ids = ids; self.total = total; self.truncated = truncated }
}
