import CoreDomain
import Foundation

/// Paged list views of `ZenTaoProviderAdapter`. Ported from zentao_adapter.dart.
extension ZenTaoProviderAdapter {
    /// Bugs scoped to one product. REST v1 ignores `browseType`, so the tab views go through the classic
    /// `bug-browse-...json` channel; a nil browseType keeps the plain REST list.
    public func listProductBugs(productId: String, browseType: String?) async -> Outcome<TicketPage> {
        await zenGuard {
            let limit = ZenTaoSourceLists.pageLimit
            var out: [Ticket] = []
            var seen = Set<String>()
            var total = 0
            for page in 1...50 {
                let res = (browseType ?? "").isEmpty
                    ? try await client.productBugs(productId, page: page, limit: limit)
                    : try await client.classicProductBugs(productId, browseType: browseType!, pageID: page)
                if res.total > 0 { total = res.total }
                var added = 0
                for bug in res.bugs {
                    let id = bug.idString
                    if id.isEmpty || !seen.insert(id).inserted { continue }
                    out.append(productBug(normalizeZenTao(bug, type: .bug, accountId: accountId, baseUrl: client.baseUrl), productId))
                    added += 1
                }
                if added == 0 { break }
                if total > 0 && out.count >= total { break }
            }
            return TicketPage(tickets: out, nextCursor: out.compactMap(\.updatedAt).max().map(ZenTaoDayParser.iso8601))
        }
    }

    /// One page (1-based) of a product's server-side bug view `browseType`.
    public func listProductBugsPage(productId: String, browseType: String, page: Int, limit: Int,
                                    sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage> {
        await zenGuard {
            let res = try await client.classicProductBugs(productId, browseType: browseType, recPerPage: limit, pageID: page,
                                                          orderBy: zentaoOrderBy(sort, bug: true), cancel: cancel)
            // ZenTao's pager answers a page past the end with the first page again, so "more" comes from the
            // view's total, never from a page being full.
            return ViewPage(
                tickets: res.bugs.filter { !$0.idString.isEmpty }.map {
                    productBug(normalizeZenTao($0, type: .bug, accountId: accountId, baseUrl: client.baseUrl), productId)
                },
                total: res.total, hasMore: page * limit < res.total)
        }
    }

    /// One page of an execution's server-side task view `browseType` (ZenTao's `wait`/`doing`/`done`/... views).
    public func listExecutionTasksPage(executionId: String, browseType: String, page: Int, limit: Int,
                                       sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage> {
        await zenGuard {
            let res = try await client.classicExecutionTasks(executionId, browseType: browseType, recPerPage: limit, pageID: page,
                                                             orderBy: zentaoOrderBy(sort, bug: false), cancel: cancel)
            var seen = Set<String>()
            let tickets = res.tasks.filter { !$0.idString.isEmpty && seen.insert($0.idString).inserted }.map { task -> Ticket in
                var t = normalizeZenTao(task, type: .task, accountId: accountId, baseUrl: client.baseUrl)
                t.labels.append(zentaoExecutionLabel(executionId))
                return t
            }
            // As with bugs, ZenTao's pager answers a page past the end with the first page again.
            return ViewPage(tickets: tickets, total: res.total, hasMore: page * limit < res.total)
        }
    }

    /// The bugs of execution `executionId` that task `taskId` may have, read from its bug list sorted by task,
    /// highest first: reading stops at the first bug of a lower task, so a recent task costs one page. Says how
    /// far the pages read cover - the whole list (`complete`), or every task above `above`. When ZenTao does not
    /// sort by task, it reads on until the end, or `maxPages` pages of `limit`.
    public func listTaskBugs(executionId: String, taskId: Int, limit: Int = 100, maxPages: Int = 5) async -> Outcome<ZenTaoTaskBugsRead> {
        await zenGuard {
            var bugs: [Ticket] = []
            var sorted = true
            var lowest: Int?
            for page in 1...max(maxPages, 1) {
                let res = try await client.classicExecutionBugs(executionId, recPerPage: limit, pageID: page, orderBy: "task_desc,id_desc")
                for bug in res.bugs where !bug.idString.isEmpty {
                    let task = zentaoInt(bug.task) ?? 0
                    if let l = lowest, task > l { sorted = false }
                    lowest = task
                    bugs.append(normalizeZenTao(bug, type: .bug, accountId: accountId, baseUrl: client.baseUrl))
                }
                // A page past the end answers the first page again, so the total ends the list, not a short page.
                if page * limit >= res.total { return ZenTaoTaskBugsRead(bugs: bugs, complete: true, above: nil) }
                // Bugs with the task's id cannot come after a lower task's.
                if sorted, let l = lowest, l < taskId { break }
            }
            return ZenTaoTaskBugsRead(bugs: bugs, complete: false, above: sorted ? lowest : nil)
        }
    }

    private func productBug(_ ticket: Ticket, _ productId: String) -> Ticket {
        var t = ticket
        t.labels.append(zentaoProductLabel(productId))
        return t
    }
}
