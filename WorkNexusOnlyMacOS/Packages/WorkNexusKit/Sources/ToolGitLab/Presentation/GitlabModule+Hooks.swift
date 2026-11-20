import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/gitlab/gitlab_module.dart (`buildDetail`, `buildActions`, `buildDetailSidebar`, `metrics`)
/// The detail-panel hooks of the shared panel (`DetailPanel`, `DetailHeader`, `OriginalTab`) and the workspace metrics.
extension GitlabModule {
    public func buildDetail(ticket: Ticket, onClose: @escaping () -> Void) -> AnyView? {
        guard (ticket.externalType ?? "").lowercased() == "mergerequest", case .gitlabItem(let entity)? = ticket.providerEntity else { return nil }
        return AnyView(GitlabMrDetail(ctx: ctx, ticket: ticket, entity: entity, onClose: onClose).id(ticket.id))
    }

    public func buildActions(ticket: Ticket) -> AnyView? { AnyView(GitlabActions(ctx: ctx, ticket: ticket)) }

    public func buildDetailSidebar(ticket: Ticket) -> AnyView? {
        guard case .gitlabItem(let entity)? = ticket.providerEntity else { return nil }
        return AnyView(GitlabDetailSections(ctx: ctx, ticket: ticket, entity: entity))
    }

    /// Primary: the account's project count (cached list, then fresh). Secondary: its open merge requests.
    public func metrics(account: Account) -> AsyncStream<ToolMetrics?> {
        let stream = ctx.services.tickets.watchTickets(), model = ctx.projects(for: account.id), accountId = account.id
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                let feed = GitlabMetricsFeed(accountId: accountId, projects: { model.projects.count }) { continuation.yield($0) }
                let loader = Task { @MainActor in await model.load(); await feed.emit() }
                for await tickets in stream { feed.tickets = tickets; await feed.emit() }
                loader.cancel()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Turns the latest tickets and project count into `ToolMetrics` (a project list arriving later re-emits).
@MainActor
final class GitlabMetricsFeed {
    var tickets: [Ticket] = []
    private let accountId: String
    private let projects: () -> Int
    private let yield: (ToolMetrics) -> Void

    init(accountId: String, projects: @escaping () -> Int, yield: @escaping (ToolMetrics) -> Void) {
        self.accountId = accountId; self.projects = projects; self.yield = yield
    }

    /// Counts off the main thread (every ticket write re-counts the whole table), then yields here.
    func emit() async {
        let tickets = tickets, count = projects(), accountId = accountId
        let m = await Task.detached(priority: .utility) { ComputeGitLabMetrics()(tickets: tickets, projectCount: count, accountId: accountId) }.value
        yield(ToolMetrics(primaryCount: m.primaryCount, primaryLabel: appString("allProjects", "All projects"),
                          secondaryCount: m.secondaryCount, secondaryLabel: appString("gitlabMergeRequests", "Merge Requests")))
    }
}
