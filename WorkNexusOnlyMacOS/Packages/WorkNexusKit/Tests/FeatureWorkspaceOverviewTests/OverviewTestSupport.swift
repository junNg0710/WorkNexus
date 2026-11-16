import CoreDomain
import CoreTools
import CoreUI
import Foundation
import SwiftUI
@testable import FeatureWorkspaceOverview

func makeTicket(_ id: String, accountId: String = "acc-zt", provider: ProviderType = .zentao, key: String = "1",
                type: String? = "Task", title: String = "Test Ticket", assignee: String? = "thanh",
                status: UnifiedStatus = .inprogress, raw: String = "wait", priority: Priority = .medium,
                updatedAt: Date? = nil, labels: [String] = [], entity: TicketProviderEntity? = nil) -> Ticket {
    Ticket(id: id, accountId: accountId, projectId: "p1", providerType: provider, externalKey: key, title: title, body: "Body",
           priority: priority, status: status, providerStatus: raw, sourceHash: "h_\(id)", externalType: type, labels: labels,
           assignee: assignee, updatedAt: updatedAt, providerEntity: entity)
}

/// An in-memory `OverviewRepository` that records the commands it receives.
final class FakeOverview: OverviewRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _refreshCalls: [String] = [], _syncCalls: [String] = [], _resolved: [[String]] = []
    var workspaces: [Workspace] = [], accounts: [Account] = [], tickets: [Ticket] = []
    var dashboards: [String: ZenTaoDashboard] = [:]
    var dateFormat = "iso"
    var cached: ZenTaoDashboard?
    var refreshResult: Outcome<Void> = .success(())
    var syncResult: Outcome<Void> = .success(())
    var resolveResult: Outcome<String> = .success("ticket-1")
    var syncDelay: Duration = .zero

    var refreshCalls: [String] { lock.withLock { _refreshCalls } }
    var syncCalls: [String] { lock.withLock { _syncCalls } }
    var resolved: [[String]] { lock.withLock { _resolved } }

    private static func once<T: Sendable>(_ v: T) -> AsyncStream<T> { AsyncStream { $0.yield(v); $0.finish() } }
    func watchWorkspaces() -> AsyncStream<[Workspace]> { Self.once(workspaces) }
    func watchAccounts() -> AsyncStream<[Account]> { Self.once(accounts) }
    func watchTickets() -> AsyncStream<[Ticket]> { Self.once(tickets) }
    func watchDateFormat() -> AsyncStream<String> { Self.once(dateFormat) }
    func watchDashboard(accountId: String) -> AsyncStream<ZenTaoDashboard?> { Self.once(dashboards[accountId]) }
    func cachedDashboard(accountId: String) async -> ZenTaoDashboard? { cached }
    func refreshDashboard(accountId: String) async -> Outcome<Void> {
        lock.withLock { _refreshCalls.append(accountId) }
        // A successful fetch leaves a fresh snapshot behind, as the real repository does.
        if case .success = refreshResult {
            lock.withLock { cached = ZenTaoDashboard(accountId: accountId, profile: ZenTaoDashboardProfile(account: "me", realname: "Me"), fetchedAt: Date()) }
        }
        return refreshResult
    }
    func syncAssignedWork(accountId: String) async -> Outcome<Void> {
        lock.withLock { _syncCalls.append(accountId) }
        if syncDelay > .zero { try? await Task.sleep(for: syncDelay) }
        return syncResult
    }
    func resolveZenTaoTicket(host: String, type: String, id: String) async -> Outcome<String> {
        lock.withLock { _resolved.append([host, type, id]) }
        return resolveResult
    }
}

/// A minimal ZenTao-like tool: its Executions section and a fixed metrics pair.
@MainActor
struct StubZenTaoTool: ToolModule {
    var providerType: ProviderType { .zentao }
    var roleLabel: String { "Developer" }
    var sections: [ToolSection] {
        [ToolSection(id: "zentao.bugs", label: "Bugs", systemImage: "ladybug", scopeKind: .product),
         ToolSection(id: "zentao.tasks", label: "Tasks", systemImage: "checklist", scopeKind: .project),
         ToolSection(id: "zentao.sprints", label: "Executions", systemImage: "rectangle.split.3x1", scopeKind: .project)]
    }
    func buildNavPane(account: Account, location: ToolLocation) -> AnyView { AnyView(EmptyView()) }
    func buildSection(account: Account, location: ToolLocation) -> AnyView { AnyView(EmptyView()) }
    func metrics(account: Account) -> AsyncStream<ToolMetrics?> {
        AsyncStream { $0.yield(ToolMetrics(primaryCount: 14, primaryLabel: "Open bugs", secondaryCount: 6, secondaryLabel: "Open tasks")); $0.finish() }
    }
}

@MainActor
func makeModel(_ repo: FakeOverview, activeWorkspaceId: String? = nil) -> OverviewModel {
    OverviewModel(repository: repo, nav: AppNavController(defaultSection: { _ in "default" }),
                  registry: ToolRegistry([StubZenTaoTool()]), activeWorkspaceId: activeWorkspaceId)
}
