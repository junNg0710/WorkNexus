import CoreDomain
import Foundation

/// Ported from: lib/tools/zentao/data/services/zentao_workflow_actions.dart
/// `ZenTaoWorkflowService` over each account's pooled ZenTao client. Every action shows its outcome at once
/// (through the `ZenTaoOptimisticRunner`), then refreshes the ticket - or puts it back on failure.
public struct ZenTaoWorkflowActions: ZenTaoWorkflowService {
    private let runner: ZenTaoOptimisticRunner
    private let adapters: ZenTaoAdapterProvider
    private let clients: ZenTaoClientProvider

    public init(runner: ZenTaoOptimisticRunner, adapters: ZenTaoAdapterProvider, clients: ZenTaoClientProvider) {
        self.runner = runner; self.adapters = adapters; self.clients = clients
    }

    public func confirmBug(_ ticket: Ticket, assignee: String?, comment: String?) async -> Outcome<Void> {
        var optimistic = ticket
        optimistic.status = .todo
        optimistic.providerStatus = "active"
        optimistic.assignee = assignee ?? ticket.assignee
        return await runBugAction(ticket, optimistic) { await $0.confirmBug(ticket, assignee: assignee, comment: comment) }
    }

    public func activateBug(_ ticket: Ticket, build: String?, assignee: String?, comment: String?) async -> Outcome<Void> {
        var optimistic = ticket
        optimistic.status = .todo
        optimistic.providerStatus = "active"
        optimistic.assignee = assignee ?? ticket.assignee
        optimistic.labels = Self.withoutResolution(ticket.labels)
        return await runBugAction(ticket, optimistic) {
            await $0.activateBug(ticket, openedBuild: build, assignee: assignee, comment: comment)
        }
    }

    public func resolveBug(_ ticket: Ticket, resolution: String, build: String?, assignee: String?, comment: String?) async -> Outcome<Void> {
        // A resolved bug awaits verification (ZenTao's `resolved` maps to review), and its board column reads
        // the resolution label.
        var optimistic = ticket
        optimistic.status = .review
        optimistic.providerStatus = "resolved"
        optimistic.assignee = assignee ?? ticket.assignee
        optimistic.labels = Self.withoutResolution(ticket.labels) + ["resolution:\(resolution.lowercased())"]
        return await runBugAction(ticket, optimistic) {
            await $0.resolveBug(ticket, resolution: resolution, resolvedBuild: build, assignee: assignee, comment: comment)
        }
    }

    static func withoutResolution(_ labels: [String]) -> [String] {
        labels.filter { !$0.lowercased().hasPrefix("resolution:") }
    }

    private func runBugAction(_ ticket: Ticket, _ optimistic: Ticket,
                              _ call: @escaping @Sendable (ProviderAdapter) async -> Outcome<Bool>) async -> Outcome<Void> {
        let adapters = self.adapters
        return await runner.runOptimisticAction(ticket, optimistic) {
            guard let adapter = await adapters.adapter(accountId: ticket.accountId) else {
                return .failure(.auth("No stored credentials for this account"))
            }
            switch await call(adapter) {
            case .failure(let f): return .failure(f)
            case .success: return .success(())
            }
        }
    }

    public func closeBug(_ ticket: Ticket, comment: String?) async -> Outcome<Void> {
        var optimistic = ticket
        optimistic.status = .done
        optimistic.providerStatus = "closed"
        return await run(ticket, optimistic) { try await $0.closeBug(ticket.externalKey, comment: comment) }
    }

    public func runTaskAction(_ ticket: Ticket, _ action: ZenTaoTaskAction, _ input: ZenTaoTaskActionInput) async -> Outcome<Void> {
        let raw: String
        switch action {
        case .start, .restart, .activate: raw = "doing"
        case .pause: raw = "pause"
        case .finish: raw = "done"
        case .close: raw = "closed"
        case .cancel: raw = "cancel"
        }
        var optimistic = ticket
        optimistic.status = mapZenTaoStatus(.task, raw)
        optimistic.providerStatus = raw
        return await run(ticket, optimistic) { try await $0.runTaskAction(ticket, action, input) }
    }

    /// Nothing is shown ahead of ZenTao's answer: a ticket that could not be deleted stays as it is.
    public func deleteTicket(_ ticket: Ticket) async -> Outcome<Void> {
        guard let client = await clients.zenTaoClient(accountId: ticket.accountId) else {
            return .failure(.auth("ZenTao account is not signed in"))
        }
        do {
            try await ZenTaoWorkflow(client: client).delete(kind: (ticket.externalType ?? "").lowercased(), id: ticket.externalKey)
            return .success(())
        } catch let e as ZenTaoError {
            return .failure(e.workflowFailure)
        } catch {
            return .failure(.unexpected("ZenTao delete failed: \(error)"))
        }
    }

    private func run(_ ticket: Ticket, _ optimistic: Ticket, _ action: @escaping @Sendable (ZenTaoWorkflow) async throws -> Void) async -> Outcome<Void> {
        let clients = self.clients
        return await runner.runOptimisticAction(ticket, optimistic) {
            guard let client = await clients.zenTaoClient(accountId: ticket.accountId) else {
                return .failure(.auth("ZenTao account is not signed in"))
            }
            do {
                try await action(ZenTaoWorkflow(client: client))
                return .success(())
            } catch let e as ZenTaoError {
                return .failure(e.workflowFailure)
            } catch {
                // Anything else (an unreadable stored account, a bad server URL) still ends as a failure, so
                // the optimistic change is put back.
                return .failure(.unexpected("ZenTao action failed: \(error)"))
            }
        }
    }
}
