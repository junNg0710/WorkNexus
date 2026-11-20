/// Not in the Flutter app: ZenTao's departments as ready-made teams.
import Foundation

/// A ZenTao user and the department they sit in (0: none).
public struct ZenTaoDepartmentUser: Equatable, Sendable {
    public var login: String
    public var name: String
    public var dept: Int
    public init(login: String, name: String, dept: Int) { self.login = login; self.name = name; self.dept = dept }
}

/// A department as a team: its people and those of every department under it, where it sits in the tree.
public struct ZenTaoDepartmentTeam: Equatable, Sendable, Identifiable {
    public var group: ZenTaoTeamGroup
    public var departmentId: Int
    /// 0 for a top department.
    public var depth: Int
    /// The team of the department above, if any.
    public var parentId: String?
    /// Whether departments with people sit under it.
    public var hasChildren: Bool
    public var id: String { group.id }
    public init(group: ZenTaoTeamGroup, departmentId: Int, depth: Int, parentId: String?, hasChildren: Bool) {
        self.group = group; self.departmentId = departmentId; self.depth = depth; self.parentId = parentId; self.hasChildren = hasChildren
    }
}

public extension ZenTaoTeamGroup {
    static let departmentPrefix = "dept:"

    /// The id of department `departmentId`'s team on `accountId`: stable, so it can be remembered and pinned.
    static func departmentId(accountId: String, departmentId: Int) -> String { "\(departmentPrefix)\(accountId):\(departmentId)" }

    /// A team ZenTao's departments give (not saved on this Mac, not edited here).
    var isDepartment: Bool { id.hasPrefix(Self.departmentPrefix) }
}
