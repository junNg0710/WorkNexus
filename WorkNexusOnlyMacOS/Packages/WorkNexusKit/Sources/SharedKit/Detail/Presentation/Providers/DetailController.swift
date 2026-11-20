import CoreDomain
import CoreTools
import CoreUI
import Foundation
import Observation

/// Ported from: lib/shared/detail/presentation/{detail_providers,detail_overlay}.dart state. Owns what the slide-over
/// renders: tickets / accounts / workspaces / projects / settings from the DB streams, one `TicketDetailModel` per
/// ticket on screen, and the image / attachment access routed through the sync services. Build one next to the
/// shell and hand it to `DetailOverlayHost`.
@MainActor @Observable
public final class DetailController {
    public let services: AppServices
    public let nav: AppNavController
    public let registry: ToolRegistry
    public var extensions: DetailExtensions

    public private(set) var tickets: [String: Ticket] = [:]
    public private(set) var accounts: [String: Account] = [:]
    public private(set) var workspaces: [String: Workspace] = [:]
    public private(set) var projects: [String: Project] = [:]
    public private(set) var settings = AppSettings()
    /// The attachment shown in the built-in viewer dialog (set by `openAttachment`, rendered by `DetailOverlayHost`).
    public var viewing: AttachmentRequest?
    private var models: [String: TicketDetailModel] = [:]
    private var tasks: [Task<Void, Never>] = []

    public init(services: AppServices, nav: AppNavController, registry: ToolRegistry, extensions: DetailExtensions = DetailExtensions()) {
        self.services = services; self.nav = nav; self.registry = registry; self.extensions = extensions
    }

    public func start() {
        guard tasks.isEmpty else { return }
        func index<T>(_ items: [T], _ id: KeyPath<T, String>) -> [String: T] {
            Dictionary(items.map { ($0[keyPath: id], $0) }, uniquingKeysWith: { a, _ in a })
        }
        tasks = [
            Task { [weak self] in
                guard let s = self?.services.tickets.watchTickets() else { return }
                // Indexed off the main thread: every ticket write rebuilt this dictionary of the whole table on it,
                // whatever the user was doing.
                for await v in s {
                    let byId = await Task.detached(priority: .utility) { Dictionary(v.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }.value
                    self?.tickets = byId
                }
            },
            Task { [weak self] in
                guard let s = self?.services.workspaces.watchAccounts() else { return }
                for await v in s { self?.accounts = index(v, \.id) }
            },
            Task { [weak self] in
                guard let s = self?.services.workspaces.watchWorkspaces() else { return }
                for await v in s { self?.workspaces = index(v, \.id) }
            },
            Task { [weak self] in
                guard let s = self?.services.workspaces.watchProjects() else { return }
                for await v in s { self?.projects = index(v, \.id) }
            },
            Task { [weak self] in
                guard let s = self?.services.settings.watch() else { return }
                for await v in s { self?.settings = v }
            },
        ]
    }

    public func stop() { tasks.forEach { $0.cancel() }; tasks = []; models.values.forEach { $0.stop() }; models = [:] }

    /// The model of an open ticket (created and started on first use).
    public func model(for id: String) -> TicketDetailModel {
        if let m = models[id] { return m }
        let m = TicketDetailModel(ticketId: id, services: services)
        models[id] = m
        if let t = tickets[id] { m.start(ticket: t) }
        return m
    }

    /// Starts a model that was created before its ticket arrived in the DB stream.
    func ensureStarted(_ id: String) { if let t = tickets[id] { models[id]?.start(ticket: t) } }

    /// Forgets models of tickets that are no longer open anywhere.
    func prune(keeping ids: Set<String>) {
        for (id, m) in models where !ids.contains(id) { m.stop(); models[id] = nil }
    }

    /// Opens an attachment: the host's hook, else the built-in viewer.
    public func openAttachment(_ ticket: Ticket, _ att: TicketAttachment) {
        if let hook = extensions.openAttachment { hook(ticket, att) } else { viewing = AttachmentRequest(ticket: ticket, attachment: att) }
    }

    public func ticket(_ id: String) -> Ticket? { tickets[id] }
    public func account(of t: Ticket) -> Account? { accounts[t.accountId] }
    public func workspace(of t: Ticket) -> Workspace? { accounts[t.accountId].flatMap { workspaces[$0.workspaceId] } }

    // MARK: Provider access

    /// An inline image of `ticket`, fetched with the account's auth (cached when the coordinator is the sync service).
    public func fetchImage(_ ticket: Ticket, _ url: String) async -> Data? {
        if let custom = extensions.imageLoader { return await custom(ticket, url) }
        if let c = services.ticketDetail as? SyncCoordinator { return await c.fetchTicketImage(ticket, url: url) }
        guard let account = accounts[ticket.accountId], let adapter = await services.sync.adapter(for: account) else { return nil }
        var path: String?, pid: String?
        if case .gitlabItem(let g)? = ticket.providerEntity { path = g.projectPath; pid = g.projectId.map(String.init) }
        return await adapter.fetchBytes(url: url, projectPath: path, projectId: pid)
    }

    /// Local path of a downloaded attachment (cached for the session), or nil.
    public func cacheAttachment(_ ticket: Ticket, _ att: TicketAttachment) async -> String? {
        if let c = services.ticketDetail as? SyncCoordinator { return await c.cacheAttachment(ticket, att) }
        guard let account = accounts[ticket.accountId], let adapter = await services.sync.adapter(for: account),
              let data = await adapter.downloadBytes(url: att.url) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(att.id)_\(att.title)")
        return (try? data.write(to: url)) != nil ? url.path : nil
    }
}

public extension DetailController {
    /// Videos above this are only framed once opened (and so downloaded): a ticket's timeline should not pull in every
    /// large recording up front. Matches chat's default auto-download limit.
    static let thumbnailAutoDownloadBytes = 20 * 1024 * 1024

    /// A still frame (PNG bytes) of a video attachment for the timeline: grabbed from the stream when the provider has
    /// one (no download), else from the downloaded file when it is small enough; nil when neither works.
    func attachmentThumbnail(_ ticket: Ticket, _ att: TicketAttachment) async -> Data? {
        if let sync = services.ticketDetail as? SyncCoordinator, let request = await sync.attachmentStream(ticket, att),
           let still = await AppVideoStills.frame(from: request) { return still }
        if (att.size ?? 0) > Self.thumbnailAutoDownloadBytes { return nil }
        guard let path = await cacheAttachment(ticket, att) else { return nil }
        return await VideoThumbnailer.shared.thumbnail(of: path)
    }
}

public struct AttachmentRequest: Identifiable {
    public let id = UUID()
    public var ticket: Ticket
    public var attachment: TicketAttachment
}
