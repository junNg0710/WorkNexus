/// Not in the Flutter app.
import CoreDomain
import Foundation

/// ZenTao's departments as teams, read over each account's pooled client: the department tree (`GET /departments`)
/// and who sits where (`GET /users`, page by page).
public struct RestZenTaoDepartmentTeams: ZenTaoDepartmentTeamSource {
    private let clients: ZenTaoClientProvider
    /// Most pages of the user list read (of `pageSize` each).
    static let pages = 50
    static let pageSize = 1000

    public init(clients: ZenTaoClientProvider) { self.clients = clients }

    public func departmentTeams(accountId: String) async -> Outcome<[ZenTaoDepartmentTeam]> {
        guard let client = await clients.zenTaoClient(accountId: accountId) else { return .failure(.auth("ZenTao account is not signed in")) }
        do {
            let departments = try await client.departments().compactMap { d -> ZenTaoDepartment? in
                guard let id = zentaoInt(d["id"]), id > 0 else { return nil }
                let name = (str(d["name"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return ZenTaoDepartment(id: id, name: name, parentId: zentaoInt(d["parent"]) ?? 0, path: name, order: zentaoInt(d["order"]) ?? 0)
            }
            let users = try await client.allUsers(pageSize: Self.pageSize, maxPages: Self.pages).compactMap { u -> ZenTaoDepartmentUser? in
                guard let login = u.account, !login.isEmpty else { return nil }
                return ZenTaoDepartmentUser(login: login, name: u.realname ?? login, dept: u.dept ?? 0)
            }
            let teams = BuildDepartmentTeams()(accountId: accountId, departments: departments, users: users)
            // What was read, for when a team is missing: departments, people and how many of them say where they sit.
            Diagnostics.info("zentao", "Department teams: \(departments.count) departments, \(users.count) people "
                             + "(\(users.filter { $0.dept > 0 }.count) with a department), \(teams.count) teams")
            return .success(teams)
        } catch let f as Failure { return .failure(f) }
        catch let e as ZenTaoError {
            if case .format = e { return .failure(.parse("ZenTao sent unreadable departments")) }
            return .failure(.network(e.message.isEmpty ? "ZenTao request failed" : e.message))
        } catch { return .failure(.parse("ZenTao sent unreadable departments")) }
    }
}
