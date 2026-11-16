import CoreDomain

/// Ported from: lib/features/workspace_overview/domain/usecases/rank_dashboard_executions.dart
/// The executions worth a glance first: running ones before the rest, then the soonest to end (undated last), at
/// most `limit`.
public struct RankDashboardExecutions: Sendable {
    public init() {}

    public func callAsFunction(_ executions: [ZenTaoDashboardExecution], limit: Int = 3) -> [ZenTaoDashboardExecution] {
        let sorted = executions.sorted { a, b in
            let ra = Self.rank(a), rb = Self.rank(b)
            if ra != rb { return ra < rb }
            switch (a.end, b.end) {
            case let (x?, y?): return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return false
            }
        }
        return Array(sorted.prefix(limit))
    }

    private static func rank(_ e: ZenTaoDashboardExecution) -> Int { e.status == "doing" ? 0 : 1 }
}
