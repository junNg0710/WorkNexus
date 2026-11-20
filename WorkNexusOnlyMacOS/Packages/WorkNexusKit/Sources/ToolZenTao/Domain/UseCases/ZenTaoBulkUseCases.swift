import CoreDomain
import Foundation

/// What a team leader can do to many tickets at once. Not in the Flutter app.
public enum ZenTaoBulkAction: Equatable, Sendable {
    /// `comment`: the note left on every ticket (ZenTao's assign form has one). `left`: the hours left given to the tasks
    /// that have none (ZenTao will not hand an unfinished task over without them); the others keep their own.
    case assign(login: String, comment: String?, left: Double? = nil)
    /// ZenTao's priority: 1 urgent, 2 high, 3 medium, 4 low.
    case priority(Int)
    case close
}

public enum ZenTaoBulkSkipReason: Equatable, Sendable {
    /// ZenTao does not offer the action on the ticket in its state (a bug that is not resolved cannot be closed).
    case notAllowed
    /// The ticket already is what the action would make it.
    case unchanged
    /// The person is not on the ticket's execution (task) or product (bug) team, so ZenTao would refuse it.
    case notMember
    /// An unfinished task with no hours left on record, and none were given: ZenTao refuses to assign it.
    case needsHours
}

/// A task ZenTao will not assign without hours left: not done, with none on record.
public struct NeedsHoursLeft: Sendable {
    public init() {}
    public func callAsFunction(_ ticket: Ticket) -> Bool {
        guard case .zentaoTask(let task)? = ticket.providerEntity else { return false }
        if ticket.providerStatus.trimmingCharacters(in: .whitespaces).lowercased() == "done" { return false }
        return (task.left ?? 0) <= 0
    }
}

public struct ZenTaoBulkSkip: Equatable, Sendable {
    public var ticket: Ticket
    public var reason: ZenTaoBulkSkipReason
}

/// The tickets a bulk action will change and those it leaves alone, each with why.
public struct ZenTaoBulkPlan: Equatable, Sendable {
    public var tickets: [Ticket]
    public var skipped: [ZenTaoBulkSkip]
    public var isEmpty: Bool { tickets.isEmpty }

    public func skipped(_ reason: ZenTaoBulkSkipReason) -> [Ticket] { skipped.filter { $0.reason == reason }.map(\.ticket) }
}

public struct PlanBulkAction: Sendable {
    public init() {}

    private func isTask(_ t: Ticket) -> Bool {
        if case .zentaoTask? = t.providerEntity { return true }
        return (t.externalType ?? "").lowercased() == "task"
    }

    /// `canTake`: whether a person may hold a ticket (on its team); unknown when nil, so nobody is skipped for it.
    public func callAsFunction(_ tickets: [Ticket], _ action: ZenTaoBulkAction,
                               canTake: ((Ticket, String) -> Bool)? = nil) -> ZenTaoBulkPlan {
        var run: [Ticket] = []
        var skipped: [ZenTaoBulkSkip] = []
        for t in tickets {
            if let reason = skip(t, action, canTake) { skipped.append(ZenTaoBulkSkip(ticket: t, reason: reason)) } else { run.append(t) }
        }
        return ZenTaoBulkPlan(tickets: run, skipped: skipped)
    }

    private func skip(_ t: Ticket, _ action: ZenTaoBulkAction, _ canTake: ((Ticket, String) -> Bool)?) -> ZenTaoBulkSkipReason? {
        switch action {
        case .assign(let login, _, let left):
            let canAssign = isTask(t) ? ListZenTaoTaskActions()(t).canAssign : ListZenTaoBugActions()(t).canAssign
            if !canAssign { return .notAllowed }
            if (t.assignee ?? "") == login { return .unchanged }
            if canTake?(t, login) == false { return .notMember }
            return NeedsHoursLeft()(t) && (left ?? 0) <= 0 ? .needsHours : nil
        case .priority(let pri):
            if !zentaoIsOpen(t) { return .notAllowed }
            return t.priority.level + 1 == pri ? .unchanged : nil
        case .close:
            let offered = isTask(t) ? ListZenTaoTaskActions()(t).actions.contains(.close) : ListZenTaoBugActions()(t).actions.contains(.close)
            return offered ? nil : .notAllowed
        }
    }
}

public struct ZenTaoBulkFailure: Equatable, Sendable {
    public var ticketId: String
    public var message: String
}

public struct ZenTaoBulkResult: Equatable, Sendable {
    public var succeeded: [String] = []
    public var failed: [ZenTaoBulkFailure] = []
    /// Tickets not tried because the run was stopped.
    public var notRun: [String] = []
    public var isClean: Bool { failed.isEmpty && notRun.isEmpty }
}

/// Runs a bulk action over a plan one ticket after another (ZenTao hands out a new session on each sign-in, so a
/// burst in parallel would sign each other out). A failure of one ticket does not stop the rest; `shouldContinue`
/// is asked before each ticket, and `progress` told after each (done, of the total).
public struct RunZenTaoBulkAction: Sendable {
    private let ops: ZenTaoBulkTicketOps
    public init(ops: ZenTaoBulkTicketOps) { self.ops = ops }

    public func callAsFunction(_ plan: ZenTaoBulkPlan, _ action: ZenTaoBulkAction,
                               shouldContinue: @Sendable () async -> Bool = { true },
                               progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async -> ZenTaoBulkResult {
        var result = ZenTaoBulkResult()
        let total = plan.tickets.count
        for (i, ticket) in plan.tickets.enumerated() {
            guard await shouldContinue() else { result.notRun = plan.tickets[i...].map(\.id); break }
            let outcome: Outcome<Void>
            switch action {
            case .assign(let login, let comment, let left):
                outcome = await ops.assign(ticket, to: login, comment: comment, left: NeedsHoursLeft()(ticket) ? left : nil)
            case .priority(let pri): outcome = await ops.setPriority(ticket, to: pri)
            case .close: outcome = await ops.close(ticket)
            }
            switch outcome {
            case .success: result.succeeded.append(ticket.id)
            case .failure(let f): result.failed.append(ZenTaoBulkFailure(ticketId: ticket.id, message: f.message))
            }
            await progress(i + 1, total)
        }
        return result
    }
}
