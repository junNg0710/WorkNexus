import CoreDomain
import Foundation

/// Server-side ticket views, written to the local ticket store as they arrive. Ported from
/// zentao_ticket_service_impl.dart.
extension ZenTaoTicketServiceImpl {
    public func syncProductBugsPage(accountId: String, productId: String, browseType: String, page: Int, limit: Int,
                                    sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage> {
        guard await accounts.account(id: accountId) != nil else { return .failure(.auth("ZenTao account not found")) }
        guard let adapter = await adapters.adapter(accountId: accountId) else { return .failure(.auth("No stored credentials for this account")) }
        return await store(await adapter.listProductBugsPage(productId: productId, browseType: browseType, page: page,
                                                             limit: limit, sort: sort, cancel: cancel))
    }

    public func syncExecutionTasksPage(accountId: String, executionId: String, browseType: String, page: Int, limit: Int,
                                       sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage> {
        guard await accounts.account(id: accountId) != nil else { return .failure(.auth("ZenTao account not found")) }
        guard let adapter = await adapters.adapter(accountId: accountId) else { return .failure(.auth("No stored credentials for this account")) }
        return await store(await adapter.listExecutionTasksPage(executionId: executionId, browseType: browseType, page: page,
                                                                limit: limit, sort: sort, cancel: cancel))
    }

    private func store(_ res: Outcome<ViewPage>) async -> Outcome<ViewPage> {
        if case .success(let page) = res { _ = await tickets.upsertTickets(page.tickets) }
        return res
    }

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
