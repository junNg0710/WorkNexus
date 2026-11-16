import CoreDomain
import Foundation

/// A person's work across every execution and product, for a team leader. Not in the Flutter app.
extension ZenTaoProviderAdapter {
    /// The numeric id of ZenTao user `login`, from the user list (read once per adapter).
    public func userId(of login: String) async -> Outcome<String> {
        await zenGuard {
            if let known = lock.withLock({ userIds[login] }) { return known }
            if !lock.withLock({ userIdsLoaded }) {
                let res = try await client.users(limit: 1000)
                lock.withLock {
                    for u in res.users { if let account = u.account, let id = u.id { userIds[account] = id } }
                    userIdsLoaded = true
                }
            }
            guard let id = lock.withLock({ userIds[login] }) else {
                throw ZenTaoError.http(status: nil, message: "ZenTao has no user \\(login)", hasResponse: false)
            }
            return id
        }
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
