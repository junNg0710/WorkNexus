import CoreDomain
import Foundation

/// Ported from: lib/shared/sync/data/sync_coordinator.dart
/// Provider-agnostic coordinator implementing `TicketDetailService` and `AccountSyncService`. Registered once, so its
/// adapter pool is the only one. Concurrent syncs of one account share a single in-flight task; writes go through
/// `TicketStore`, which writes only the rows that changed. Tool-specific behaviour is injected via `SyncExtensions`.
public actor SyncCoordinator: AccountSyncService, TicketDetailService {
    private let workspaces: WorkspaceRepository
    private let credentials: CredentialStore
    private let statusRepo: SyncStatusRepository?
    private let attachmentCache: AttachmentFileCache
    private let store: TicketStore
    private let pool: ProviderAdapterPool
    /// Cache of the sidebar's container lists (products / projects), painted from disk before the network answers.
    public nonisolated let listCache: SourceListCache
    private var extensions: SyncExtensions
    private let imageCache = ByteLruCache()
    private var imageMisses: [String: Date] = [:]
    private static let imageRetryAfter: TimeInterval = 5 * 60
    private var accountSyncs: [String: Task<Outcome<Int>, Never>] = [:]

    public init(tickets: TicketRepository, workspaces: WorkspaceRepository, comments: CommentRepository,
                activity: ActivityRepository, credentials: CredentialStore, registry: ProviderAdapterRegistry,
                statusRepository: SyncStatusRepository? = nil, attachmentCache: AttachmentFileCache = AttachmentFileCache(),
                listCache: SourceListCache = SourceListCache(), detailWriter: DetailWriting? = nil,
                extensions: SyncExtensions = SyncExtensions()) {
        self.workspaces = workspaces; self.credentials = credentials; self.statusRepo = statusRepository
        self.attachmentCache = attachmentCache; self.listCache = listCache; self.extensions = extensions
        store = TicketStore(tickets: tickets, workspaces: workspaces, comments: comments, activity: activity, writer: detailWriter)
        pool = ProviderAdapterPool(accountLookup: { id in
            await firstValue(of: workspaces.watchAccounts())?.first { $0.id == id }
        }, credentials: credentials, registry: registry)
    }

    /// Registers provider-specific hooks (reviewers, member lists) the composition root wires from tool modules.
    public func setExtensions(_ e: SyncExtensions) { extensions = e }

    // MARK: AccountSyncService

    public func sync(accountId: String) async -> Outcome<Void> {
        guard let account = await account(accountId) else { return .failure(.notFound("No such account")) }
        return await syncAccount(account).map { _ in () }
    }

    public func adapter(for account: Account) async -> ProviderAdapter? {
        guard let ref = account.credentialsRef, let secret = await credentials.read(ref) else { return nil }
        return pool.build(account, secret: secret)
    }

    /// Syncs `account`'s assigned tickets into the DB; returns how many were fetched. A sync already running for the
    /// account is shared instead of fetched again (the launch sync and the Overview's can ask at once).
    public func syncAccount(_ account: Account) async -> Outcome<Int> {
        if let running = accountSyncs[account.id] { return await running.value }
        let task = Task { await self.trackSync(account.id) { await self.runSync(account) } }
        accountSyncs[account.id] = task
        let result = await task.value
        accountSyncs[account.id] = nil
        return result
    }

    /// Runs `action` for `accountId`, reporting the account's sync status around it.
    public func trackSync<T: Sendable>(_ accountId: String, _ action: () async -> Outcome<T>) async -> Outcome<T> {
        await trackSyncStatus(statusRepo, accountId: accountId, action)
    }

    private func runSync(_ account: Account) async -> Outcome<Int> {
        guard let ref = account.credentialsRef else { return .failure(.auth("No stored credentials for this account")) }
        guard let secret = await credentials.read(ref) else { return .failure(.auth("Stored credentials not found in keychain")) }
        guard let adapter = pool.build(account, secret: secret) else {
            return .failure(.unexpected("\(account.providerType.displayName) sync is not implemented yet"))
        }
        switch await adapter.listAssignedTickets(sinceCursor: nil) {
        case .failure(let f): return .failure(f)
        case .success(let page):
            await store.writeSynced(account, page.tickets)
            return .success(page.tickets.count)
        }
    }

    private func account(_ id: String) async -> Account? { await firstValue(of: workspaces.watchAccounts())?.first { $0.id == id } }

    /// The pooled adapter for an account id (nil when the account or its secret is gone).
    public func adapterFor(_ accountId: String) async -> ProviderAdapter? { await pool.forAccount(accountId) }

    /// Writes tickets a list fetch returned (used by tool boards that fetch pages themselves).
    public func upsert(_ account: Account, _ tickets: [Ticket]) async { await store.writeSynced(account, tickets) }

    // MARK: Container lists (sidebar trees)

    public func listProducts(accountId: String) async -> Outcome<[ProviderProduct]> {
        guard let adapter = await adapterFor(accountId) else { return .failure(.auth("No stored credentials for this account")) }
        let res = await adapter.listProducts()
        if case .success(let v) = res { await listCache.saveProducts(accountId, v) }
        return res
    }

    public func cachedProducts(accountId: String) async -> [ProviderProduct]? { await listCache.readProducts(accountId) }

    public func listProjects(accountId: String) async -> Outcome<[ProviderProject]> {
        guard let adapter = await adapterFor(accountId) else { return .failure(.auth("No stored credentials for this account")) }
        let res = await adapter.listProjects()
        guard case .success(let v) = res else { return res }
        let named = await listCache.withKnownProgramNames(accountId, v)
        await listCache.saveProjects(accountId, named)
        return .success(named)
    }

    public func cachedProjects(accountId: String) async -> [ProviderProject]? { await listCache.readProjects(accountId) }

    // MARK: TicketDetailService

    public func refresh(ticket: Ticket) async -> Outcome<Void> { await syncTicketDetail(ticket) }

    /// Re-fetches ticket + comments + activity into the DB. Not tracked: one ticket's refresh (and its own failures,
    /// like a deleted ticket) is no news about the account's sync.
    public func syncTicketDetail(_ ticket: Ticket) async -> Outcome<Void> {
        guard let adapter = await adapterFor(ticket.accountId) else { return .success(()) }
        let detail: Ticket
        switch await adapter.getTicket(ticket) {
        case .failure(let f): return .failure(f)
        case .success(let v): detail = v
        }
        var merged = detail
        merged.id = ticket.id; merged.accountId = ticket.accountId; merged.projectId = ticket.projectId
        merged.labels = mergeDetailLabels(detail.labels, ticket.labels)
        merged.providerEntity = preserveLabelColors(detail.providerEntity, ticket.providerEntity)
        // Only rows that differ are written, compared against the stored row (the server's answer replaces a guess).
        await store.writeIfChanged(merged)
        async let comments = adapter.listComments(ticket)
        async let activity = adapter.listActivity(ticket)
        let (c, a) = await (comments, activity)
        // One write: the new comments never show next to the old activity.
        await store.replaceDetail(ticket.id, comments: c.value, activity: a.value)
        return .success(())
    }

    public func postComment(ticket: Ticket, body: String) async -> Outcome<Void> {
        guard let adapter = await adapterFor(ticket.accountId) else { return .failure(.auth("No stored credentials for this account")) }
        if case .failure(let f) = await adapter.postComment(ticket, body: body) { return .failure(f) }
        return await syncTicketDetail(ticket)
    }

    public func assignTicket(_ ticket: Ticket, assignee: String, comment: String? = nil, left: Double? = nil) async -> Outcome<Void> {
        guard let adapter = await adapterFor(ticket.accountId) else { return .failure(.auth("No stored credentials for this account")) }
        if case .failure(let f) = await adapter.assignTicket(ticket, assignee: assignee, comment: comment, left: left) { return .failure(f) }
        return await syncTicketDetail(ticket)
    }

    /// GitLab/GitHub reviewers, through the `SyncExtensions.setReviewers` hook.
    public func setReviewers(_ ticket: Ticket, logins: [String]) async -> Outcome<Void> {
        guard let adapter = await adapterFor(ticket.accountId) else { return .failure(.auth("No stored credentials for this account")) }
        guard let res = await extensions.setReviewers?(adapter, ticket, logins) else {
            return .failure(.unexpected("Reviewers are GitLab/GitHub only"))
        }
        if case .failure(let f) = res { return .failure(f) }
        return await syncTicketDetail(ticket)
    }

    /// People a ticket can be assigned to (member lists via `SyncExtensions.listUsers`, else the adapter's own list).
    public func listUsers(for ticket: Ticket) async -> Outcome<[ProviderUser]> {
        guard let adapter = await adapterFor(ticket.accountId) else { return .success([]) }
        if let res = await extensions.listUsers?(adapter, ticket) { return res }
        return await adapter.listUsers()
    }

    /// Applies `optimistic` to the DB at once, runs `action`, then refreshes; any failure rolls back to `ticket`.
    public func runOptimisticAction(_ ticket: Ticket, optimistic: Ticket, _ action: () async -> Outcome<Void>) async -> Outcome<Void> {
        await optimisticallyUpdate(optimistic)
        let res = await action()
        if case .failure(let f) = res { await rollback(ticket); return .failure(f) }
        // The action already landed on the server: a failed refresh must not roll the ticket back.
        _ = await syncTicketDetail(ticket)
        return .success(())
    }

    public func optimisticallyUpdate(_ ticket: Ticket) async { await store.overwrite(ticket) }
    public func rollback(_ ticket: Ticket) async { await store.overwrite(ticket) }

    // MARK: Images & attachments

    /// An image of a ticket (description / comment inline image) fetched with the account's auth; cached in memory,
    /// and a "no" answer rests `imageRetryAfter` so dead links don't cost a request (and, on ZenTao, a re-login) each time.
    public func fetchTicketImage(_ ticket: Ticket, url: String) async -> Data? {
        let key = "\(ticket.accountId)|\(url)"
        if let cached = imageCache.get(key) { return cached }
        let now = Date()
        if let missed = imageMisses[key] {
            if now.timeIntervalSince(missed) < Self.imageRetryAfter { return nil }
            imageMisses[key] = nil
        }
        var projectPath: String?, projectId: String?
        if case .gitlabItem(let g)? = ticket.providerEntity { projectPath = g.projectPath; projectId = g.projectId.map(String.init) }
        guard let adapter = await adapterFor(ticket.accountId) else { return nil }
        let bytes = await adapter.fetchBytes(url: url, projectPath: projectPath, projectId: projectId)
        if let bytes { imageCache.put(key, bytes) } else { imageMisses[key] = now }
        return bytes
    }

    /// Downloads an attachment into the on-disk cache (reused within the session) and returns its local path.
    public func cacheAttachment(_ ticket: Ticket, _ att: TicketAttachment) async -> String? {
        guard let adapter = await adapterFor(ticket.accountId) else { return nil }
        let safe = Self.safeName(att.title)
        if let existing = attachmentCache.existing(att.id, safe) { return existing }
        guard let bytes = await adapter.downloadBytes(url: att.url) else { return nil }
        return try? attachmentCache.store(att.id, safe, bytes)
    }

    /// Request (url + auth headers) a player can stream an attachment from, or nil.
    public func attachmentStream(_ ticket: Ticket, _ att: TicketAttachment) async -> MediaRequest? {
        guard let url = att.streamUrl, let adapter = await adapterFor(ticket.accountId) else { return nil }
        return await adapter.streamRequest(url: url)
    }

    public func attachmentStorageBytes() -> Outcome<Int> { .success(attachmentCache.sizeBytes()) }

    public func clearAttachmentStorage() -> Outcome<Void> { attachmentCache.purge(); return .success(()) }

    /// Wipes the attachment cache (call once at launch: the cache is per session).
    public func purgeAttachmentCache() { attachmentCache.purge() }

    /// Copies a cached attachment into `~/Downloads` and returns the new path (nil if there is no Downloads folder).
    public func saveAttachmentToDownloads(cachedPath: String, name: String) -> String? {
        let fm = FileManager.default
        guard let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first,
              fm.fileExists(atPath: downloads.path) else { return nil }
        let dest = downloads.appendingPathComponent(Self.safeName(name))
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(atPath: cachedPath, toPath: dest.path)
            return dest.path
        } catch { return nil }
    }

    static func safeName(_ name: String) -> String {
        String(name.map { "/\\:*?\"<>|".contains($0) ? "_" : $0 })
    }
}

private extension TicketStore {
    func overwrite(_ ticket: Ticket) async { _ = await writer.overwrite(ticket: ticket) }
}
