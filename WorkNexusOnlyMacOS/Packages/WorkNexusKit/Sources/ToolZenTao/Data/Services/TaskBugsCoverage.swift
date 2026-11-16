import Foundation

/// Ported from: lib/tools/zentao/data/services/task_bugs_coverage.dart
/// What one read of an execution's bug list (sorted by task, highest first) covered, so opening another task of
/// the execution soon after reads nothing again: the whole list (`complete`), the bugs of every task above
/// `above`, and in any case those of the `tasks` it was read for.
struct TaskBugsCoverage {
    /// How long a read stays good: bugs filed or relinked meanwhile show on the next read after it.
    static let ttl: TimeInterval = 5 * 60

    var at: Date
    var complete = false
    var above: Int?
    var tasks: Set<Int> = []

    /// Whether this read, still fresh at `now`, holds every bug of `task`.
    func covers(_ task: Int, now: Date) -> Bool {
        if now.timeIntervalSince(at) >= Self.ttl { return false }
        if complete || tasks.contains(task) { return true }
        if let above { return task > above }
        return false
    }
}
