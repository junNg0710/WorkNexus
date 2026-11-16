import CoreDomain
import Foundation

/// Ported from: lib/tools/zentao/data/services/zentao_ticket_service_impl.dart
/// `ZenTaoTicketService`, `ZenTaoViewPages` and `ZenTaoTaskBugs` over the pooled adapters, the ticket store
/// (`TicketRepository`, the local source of truth) and the container-list cache. View pages and task bugs live in
/// `ZenTaoTicketServiceImpl+Views.swift`.
public final class ZenTaoTicketServiceImpl: ZenTaoTicketService, ZenTaoViewPages, ZenTaoTaskBugs, @unchecked Sendable {
    let accounts: ZenTaoAccountLookup
    let adapters: ZenTaoAdapterProvider
    let tickets: TicketRepository
    let cache: ZenTaoSourceListCache?

    /// What recent reads of each execution's bug list covered, by `accountId:executionId`.
    let coverageLock = NSLock()
    var taskBugsCoverage: [String: TaskBugsCoverage] = [:]

    public init(accounts: ZenTaoAccountLookup, adapters: ZenTaoAdapterProvider, tickets: TicketRepository,
                cache: ZenTaoSourceListCache? = nil) {
        self.accounts = accounts; self.adapters = adapters; self.tickets = tickets; self.cache = cache
    }

    public func fetchZenTaoTicket(host: String, type: String, id: String) async -> Outcome<String> {
        let account = await accounts.zentaoAccounts().first { URL(string: $0.baseUrl ?? "")?.host == host }
        guard let account, account.credentialsRef != nil else { return .failure(.notFound("No ZenTao account for this link")) }
        guard let adapter = await adapters.adapter(accountId: account.id) else { return .failure(.auth("ZenTao account is not signed in")) }
        let stub = Ticket(
            id: zenTaoTicketId(accountId: account.id, type: type, id: id), accountId: account.id,
            projectId: "\(account.id):\(type)", providerType: .zentao, externalKey: id,
            title: "", body: "", priority: .medium, status: .todo, providerStatus: "", sourceHash: "",
            externalType: type.prefix(1).uppercased() + type.dropFirst())
        switch await adapter.getTicket(stub) {
        case .failure(let f): return .failure(f)
        case .success(let detail):
            if case .failure(let f) = await tickets.upsertTickets([detail]) { return .failure(f) }
            return .success(detail.id)
        }
    }

    public func listProducts(accountId: String) async -> Outcome<[ProviderProduct]> {
        guard let adapter = await adapters.adapter(accountId: accountId) else { return .failure(.auth("No stored credentials for this account")) }
        let res = await adapter.listProducts()
        if case .success(let items) = res { await cache?.saveProducts(accountId: accountId, items: items) }
        return res
    }

    public func cachedProducts(accountId: String) async -> [ProviderProduct]? { await cache?.readProducts(accountId: accountId) }

    public func listProjects(accountId: String) async -> Outcome<[ProviderProject]> {
        guard let adapter = await adapters.adapter(accountId: accountId) else { return .failure(.auth("No stored credentials for this account")) }
        switch await adapter.listProjects() {
        case .failure(let f): return .failure(f)
        case .success(let fetched):
            // Program names a fetch could not get come from the last list that had them.
            let items = await cache?.withKnownProgramNames(accountId: accountId, projects: fetched) ?? fetched
            await cache?.saveProjects(accountId: accountId, items: items)
            return .success(items)
        }
    }

    public func cachedProjects(accountId: String) async -> [ProviderProject]? { await cache?.readProjects(accountId: accountId) }

    public func listProjectExecutions(accountId: String, projectId: String) async -> Outcome<[ProviderExecution]> {
        guard let adapter = await adapters.adapter(accountId: accountId) else { return .failure(.auth("No stored credentials for this account")) }
        return await adapter.listProjectExecutions(projectId: projectId)
    }

    private func messages(_ accountId: String) async -> ZenTaoMessagesAdapter? {
        await adapters.adapter(accountId: accountId) as? ZenTaoMessagesAdapter
    }

    public func fetchZenTaoMessages(accountId: String) async -> Outcome<ZenTaoRawReply> {
        guard let a = await messages(accountId) else { return .failure(.auth("No signed-in ZenTao account")) }
        return await a.fetchMessages()
    }

    public func zenTaoMessageAction(accountId: String, action: String) async -> Outcome<Void> {
        guard let a = await messages(accountId) else { return .failure(.auth("No signed-in ZenTao account")) }
        return await a.messageAction(action)
    }

    public func fetchZenTaoUserInfo(accountId: String, fields: String, limit: Int) async -> Outcome<ZenTaoRawReply> {
        guard let a = await messages(accountId) else { return .failure(.auth("No signed-in ZenTao account")) }
        return await a.fetchUserInfo(fields: fields, limit: limit)
    }
}
