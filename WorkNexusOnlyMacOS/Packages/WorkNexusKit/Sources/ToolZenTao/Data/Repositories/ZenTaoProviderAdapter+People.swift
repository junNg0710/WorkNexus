import CoreDomain
import Foundation

/// A person's work across every execution and product, for a team leader. Not in the Flutter app.
extension ZenTaoProviderAdapter {
    /// Most pages of the user list read to find someone (of `userPageSize` each).
    static let userPages = 50
    static let userPageSize = 1000

    /// The numeric id of ZenTao user `login` (case aside, as ZenTao signs in). The signed-in user's comes from their own
    /// profile; anyone else's from the user list, read page by page until they are found (read once per adapter).
    public func userId(of login: String) async -> Outcome<String> {
        await zenGuard {
            let key = login.trimmingCharacters(in: .whitespaces).lowercased()
            if let known = lock.withLock({ userIds[key] }) { return known }
            if key == client.account.lowercased(), let own = try? await ownUser() {
                lock.withLock { userIds[key] = own.id; if let account = own.account { userLogins[key] = account } }
                return own.id
            }
            if !lock.withLock({ userIdsLoaded }) {
                let users = try await client.allUsers(pageSize: Self.userPageSize, maxPages: Self.userPages,
                                                      until: { $0.account?.lowercased() == key })
                lock.withLock {
                    for u in users {
                        if let account = u.account, let id = u.id { userIds[account.lowercased()] = id; userLogins[account.lowercased()] = account }
                    }
                    userIdsLoaded = true
                }
            }
            guard let id = lock.withLock({ userIds[key] }) else {
                throw ZenTaoError.http(status: nil, message: "ZenTao has no user \(login)", hasResponse: false)
            }
            return id
        }
    }

    /// The signed-in user's id and login, from their profile (`GET /user`).
    private func ownUser() async throws -> (id: String, account: String?)? {
        let profile = asMap(try await client.userInfo()["profile"])
        guard let id = zentaoInt(profile?["id"]).map(String.init) else { return nil }
        return (id, profile?["account"] as? String)
    }

    /// `login` as ZenTao writes it, once `userId(of:)` has found them; nil before, or when ZenTao did not say.
    public func zenTaoLogin(of login: String) -> String? {
        lock.withLock { userLogins[login.trimmingCharacters(in: .whitespaces).lowercased()] }
    }

    /// One page (1-based) of what is assigned to user `userId`: tasks of every execution, or bugs of every product.
    /// Each ticket carries the membership label of the execution / product it sits in, so the board of that scope
    /// finds it too.
    public func listAssignedWorkPage(userId: String, bugs: Bool, page: Int, limit: Int, cancel: CancelSignal?) async -> Outcome<ViewPage> {
        await zenGuard {
            if bugs {
                let res = try await client.classicUserBugs(userId, recPerPage: limit, pageID: page, cancel: cancel)
                let tickets = res.bugs.filter { !$0.idString.isEmpty }.map { bug -> Ticket in
                    var t = normalizeZenTao(bug, type: .bug, accountId: accountId, baseUrl: client.baseUrl)
                    if case .zentaoBug(let b)? = t.providerEntity, let p = b.product, !p.isEmpty, p != "0" { t.labels.append(zentaoProductLabel(p)) }
                    return t
                }
                return ViewPage(tickets: tickets, total: res.total, hasMore: page * limit < res.total)
            }
            let res = try await client.classicUserTasks(userId, recPerPage: limit, pageID: page, cancel: cancel)
            var seen = Set<String>()
            let tickets = res.tasks.filter { !$0.idString.isEmpty && seen.insert($0.idString).inserted }.map { task -> Ticket in
                var t = normalizeZenTao(task, type: .task, accountId: accountId, baseUrl: client.baseUrl)
                if case .zentaoTask(let e)? = t.providerEntity, let x = e.execution, !x.isEmpty, x != "0" { t.labels.append(zentaoExecutionLabel(x)) }
                return t
            }
            return ViewPage(tickets: tickets, total: res.total, hasMore: page * limit < res.total)
        }
    }
}
