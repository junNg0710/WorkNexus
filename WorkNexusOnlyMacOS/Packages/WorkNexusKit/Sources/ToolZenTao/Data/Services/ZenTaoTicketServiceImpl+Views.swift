import CoreDomain
import Foundation

/// Server-side ticket views, written to the local ticket store as they arrive. Ported from
/// zentao_ticket_service_impl.dart.
extension ZenTaoTicketServiceImpl {
    public func syncProductBugsPage(accountId: String, productId: String, browseType: String, page: Int, limit: Int,
                                    sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage> {
        guard await accounts.account(id: accountId) != nil else { return .failure(.auth("ZenTao account not found")) }
        guard let adapter = await adapters.adapter(accountId: accountId) else { return .failure(.auth("No stored credentials for this account")) }
        let read = await PerformanceLog.measure("zentao: read bugs \(browseType) page \(page)", slowerThan: Self.slowRead) {
            await adapter.listProductBugsPage(productId: productId, browseType: browseType, page: page, limit: limit, sort: sort, cancel: cancel)
        }
        return await store(read)
    }

    public func syncExecutionTasksPage(accountId: String, executionId: String, browseType: String, page: Int, limit: Int,
                                       sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage> {
        guard await accounts.account(id: accountId) != nil else { return .failure(.auth("ZenTao account not found")) }
        guard let adapter = await adapters.adapter(accountId: accountId) else { return .failure(.auth("No stored credentials for this account")) }
        let read = await PerformanceLog.measure("zentao: read tasks \(browseType) page \(page)", slowerThan: Self.slowRead) {
            await adapter.listExecutionTasksPage(executionId: executionId, browseType: browseType, page: page, limit: limit, sort: sort, cancel: cancel)
        }
        return await store(read)
    }

    public func syncAssignedWork(accountId: String, login: String, bugs: Bool, cap: Int, cancel: CancelSignal?) async -> Outcome<ZenTaoPersonWork> {
        guard await accounts.account(id: accountId) != nil else { return .failure(.auth("ZenTao account not found")) }
        guard let adapter = await adapters.adapter(accountId: accountId) as? ZenTaoProviderAdapter else {
            return .failure(.auth("No signed-in ZenTao account"))
        }
        let userId: String
        switch await adapter.userId(of: login) {
        case .failure(let f): return .failure(f)
        case .success(let id): userId = id
        }
        // How ZenTao writes the login ("JunNg" for a "junng" typed at sign-in): the tickets carry that one.
        let real = adapter.zenTaoLogin(of: login).flatMap { $0 == login ? nil : $0 }
        let limit = 100
        var ids: [String] = []
        var seen = Set<String>()
        var total = 0
        var page = 1
        while true {
            if cancel?.isCancelled == true { return .failure(.cancelled("Reading \(login)'s work was stopped")) }
            let read = await PerformanceLog.measure("zentao: read \(bugs ? "bugs" : "tasks") of a person, page \(page)", slowerThan: Self.slowRead) {
                await adapter.listAssignedWorkPage(userId: userId, bugs: bugs, page: page, limit: limit, cancel: cancel)
            }
            switch await store(read) {
            case .failure(let f): return .failure(f)
            case .success(let v):
                total = v.total
                var added = 0
                for t in v.tickets where seen.insert(t.id).inserted { ids.append(t.id); added += 1 }
                // A page past the end answers the first again, so the total ends the read, and so does a page with nothing new.
                if !v.hasMore || added == 0 { return .success(ZenTaoPersonWork(ids: ids, total: total, truncated: false, login: real)) }
                if ids.count >= cap { return .success(ZenTaoPersonWork(ids: Array(ids.prefix(cap)), total: total, truncated: true, login: real)) }
            }
            page += 1
        }
    }

    private func store(_ res: Outcome<ViewPage>) async -> Outcome<ViewPage> {
        // Its time is written by the store itself ("db: write N tickets").
        if case .success(let page) = res { _ = await tickets.upsertTickets(page.tickets) }
        return res
    }

    /// A list page read from the server slower than this is written to the performance log.
    static var slowRead: TimeInterval { 1.5 }

    public func syncTaskBugs(accountId: String, executionId: String, taskId: String) async -> Outcome<Void> {
        guard let task = Int(taskId) else { return .success(()) }
        let key = "\(accountId):\(executionId)"
        if coverageLock.withLock({ taskBugsCoverage[key]?.covers(task, now: Date()) }) == true { return .success(()) }
        guard await accounts.account(id: accountId) != nil else { return .failure(.auth("ZenTao account not found")) }
        guard let adapter = await adapters.adapter(accountId: accountId) as? ZenTaoProviderAdapter else {
            return .failure(.auth("No signed-in ZenTao account"))
        }
        switch await adapter.listTaskBugs(executionId: executionId, taskId: task) {
        case .failure(let f): return .failure(f)
        case .success(let read):
            _ = await tickets.upsertTickets(read.bugs)
            coverageLock.withLock {
                taskBugsCoverage[key] = TaskBugsCoverage(at: Date(), complete: read.complete, above: read.above, tasks: [task])
            }
            return .success(())
        }
    }
}
