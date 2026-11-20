/// Not in the Flutter app: what the ZenTao boards derive from their tickets, kept until an input changes.
import CoreDomain
import Foundation
import SharedKit

/// One board's derived values. A view asks for the columns, the header for a count, the module tree for its counts and
/// the leader bar for the workload and the chips - each used to filter and sort every ticket again, several times per
/// redraw. Here each is worked out once per `Key` (the tickets in scope, the filters, the sort, the day).
@MainActor
final class ZentaoBoardCache {
    struct Key: Equatable {
        var revision: Int
        var leader: ZenTaoLeaderFilter
        var names: [String: String]
        /// The order of the cards (the session's, shared by every board).
        var sort: TicketSort
        var includeClosed: Bool
        var roster: [String]
        /// Deadlines are by calendar day: what is "overdue" changes at midnight.
        var day: Int
    }

    private var key: Key?
    private var taskBoard: ZenTaoTaskBoardModel?
    private var bugBoard: ZenTaoBugBoardModel?
    private var pool: [Ticket]?
    private var workload: [ZenTaoWorkload]?
    private var counts: [ZenTaoQuickFilter: Int]?
    /// How many times something was worked out (the tests read it).
    private(set) var builds = 0

    private func fresh(_ k: Key) {
        guard k != key else { return }
        key = k; taskBoard = nil; bugBoard = nil; pool = nil; workload = nil; counts = nil
    }

    func taskBoard(_ k: Key, _ make: () -> ZenTaoTaskBoardModel) -> ZenTaoTaskBoardModel {
        fresh(k)
        if let taskBoard { return taskBoard }
        builds += 1
        let v = PerformanceLog.measureSync("zentao: build task columns") { make() }; taskBoard = v; return v
    }

    func bugBoard(_ k: Key, _ make: () -> ZenTaoBugBoardModel) -> ZenTaoBugBoardModel {
        fresh(k)
        if let bugBoard { return bugBoard }
        builds += 1
        let v = PerformanceLog.measureSync("zentao: build bug columns") { make() }; bugBoard = v; return v
    }

    func pool(_ k: Key, _ make: () -> [Ticket]) -> [Ticket] {
        fresh(k)
        if let pool { return pool }
        builds += 1
        let v = PerformanceLog.measureSync("zentao: pick the tickets on the board") { make() }; pool = v; return v
    }

    func workload(_ k: Key, _ make: () -> [ZenTaoWorkload]) -> [ZenTaoWorkload] {
        fresh(k)
        if let workload { return workload }
        builds += 1
        let v = PerformanceLog.measureSync("zentao: count each person's work") { make() }; workload = v; return v
    }

    func counts(_ k: Key, _ make: () -> [ZenTaoQuickFilter: Int]) -> [ZenTaoQuickFilter: Int] {
        fresh(k)
        if let counts { return counts }
        builds += 1
        let v = PerformanceLog.measureSync("zentao: count the quick filters") { make() }; counts = v; return v
    }
}

extension ZentaoUIState {
    /// The inputs of a board's derived values. Reading them here is also what makes a view depend on them.
    func cacheKey(bugs: Bool) -> ZentaoBoardCache.Key {
        ZentaoBoardCache.Key(revision: (bugs ? bugBoard : taskBoard).revision, leader: leader(bugs: bugs), names: memberNames,
                             sort: deps.nav.boardSort, includeClosed: bugs && bugTab == .all, roster: boardMembers(bugs: bugs).map(\.account),
                             day: Int(Date().timeIntervalSince1970 / 86_400))
    }
}
