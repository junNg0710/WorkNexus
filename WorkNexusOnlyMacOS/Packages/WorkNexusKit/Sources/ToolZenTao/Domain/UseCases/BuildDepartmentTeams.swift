/// Not in the Flutter app.
import Foundation

/// ZenTao's departments as teams, in the order of its own tree (parents before their children, siblings by ZenTao's
/// order): each team holds the people of its department and of every department under it, so "VN" is all of VN.
/// Departments with nobody in them, below them included, are left out.
public struct BuildDepartmentTeams: Sendable {
    public init() {}

    public func callAsFunction(accountId: String, departments: [ZenTaoDepartment], users: [ZenTaoDepartmentUser]) -> [ZenTaoDepartmentTeam] {
        let known = Set(departments.map(\.id))
        // A department whose parent is unknown (or itself) is treated as a top one, so nothing is lost.
        let children = Dictionary(grouping: departments) { d in known.contains(d.parentId) && d.parentId != d.id ? d.parentId : 0 }
            .mapValues { $0.sorted { ($0.order, $0.id) < ($1.order, $1.id) } }
        let direct = Dictionary(grouping: users.filter { !$0.login.isEmpty }, by: \.dept)

        var out: [ZenTaoDepartmentTeam] = []
        var visited: Set<Int> = []

        /// The people of `dept` and below; appends its team (before its children's) when there is anyone.
        @discardableResult
        func visit(_ dept: ZenTaoDepartment, depth: Int, parent: String?) -> [ZenTaoDepartmentUser] {
            guard visited.insert(dept.id).inserted else { return [] }
            let teamId = ZenTaoTeamGroup.departmentId(accountId: accountId, departmentId: dept.id)
            let slot = out.count
            out.append(ZenTaoDepartmentTeam(group: ZenTaoTeamGroup(id: teamId, accountId: accountId, name: dept.name, members: []),
                                            departmentId: dept.id, depth: depth, parentId: parent, hasChildren: false))
            let before = out.count
            var people = direct[dept.id] ?? []
            for child in children[dept.id] ?? [] { people += visit(child, depth: depth + 1, parent: teamId) }
            var seen: Set<String> = []
            let members = people.filter { seen.insert($0.login).inserted }
                .map { ZenTaoTeamMember(login: $0.login, name: $0.name.isEmpty ? $0.login : $0.name) }
            if members.isEmpty {
                out.removeSubrange(slot...)
            } else {
                out[slot].group.members = members
                out[slot].hasChildren = out.count > before
            }
            return people
        }

        for top in children[0] ?? [] { visit(top, depth: 0, parent: nil) }
        return out
    }
}
