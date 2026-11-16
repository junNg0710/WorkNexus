import CoreDomain
import Foundation

/// Ported from: lib/tools/zentao/domain/repositories/zentao_view_pages.dart
/// Pages of a ZenTao server-side ticket view, stored locally as they arrive.
public protocol ZenTaoViewPages: Sendable {
    func syncProductBugsPage(accountId: String, productId: String, browseType: String, page: Int, limit: Int,
                             sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage>
    func syncExecutionTasksPage(accountId: String, executionId: String, browseType: String, page: Int, limit: Int,
                                sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage>
}

/// Ported from: lib/tools/zentao/domain/repositories/zentao_task_bugs.dart
/// Brings a ZenTao task's related bugs into the local database.
public protocol ZenTaoTaskBugs: Sendable {
    func syncTaskBugs(accountId: String, executionId: String, taskId: String) async -> Outcome<Void>
}
