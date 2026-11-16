import CoreDomain
import Foundation

/// Ported from: lib/tools/zentao/domain/repositories/zentao_view_pages.dart
/// Pages of a ZenTao server-side ticket view, stored locally as they arrive.
public protocol ZenTaoViewPages: Sendable {
    func syncProductBugsPage(accountId: String, productId: String, browseType: String, page: Int, limit: Int,
                             sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage>
    func syncExecutionTasksPage(accountId: String, executionId: String, browseType: String, page: Int, limit: Int,
                                sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage>
    /// Everything assigned to `login` across every execution (tasks) or product (bugs), read page after page up to `cap`
    /// tickets and stored locally. Not in the Flutter app (a team leader's view of a person).
    func syncAssignedWork(accountId: String, login: String, bugs: Bool, cap: Int, cancel: CancelSignal?) async -> Outcome<ZenTaoPersonWork>
}

public extension ZenTaoViewPages {
    func syncAssignedWork(accountId: String, login: String, bugs: Bool, cap: Int, cancel: CancelSignal?) async -> Outcome<ZenTaoPersonWork> {
        .failure(.unexpected("Reading a person's work is not available"))
    }
}

/// Ported from: lib/tools/zentao/domain/repositories/zentao_task_bugs.dart
/// Brings a ZenTao task's related bugs into the local database.
public protocol ZenTaoTaskBugs: Sendable {
    func syncTaskBugs(accountId: String, executionId: String, taskId: String) async -> Outcome<Void>
}
