import CoreDomain
import CoreTools
import Foundation
import Observation

public enum DetailTab: Sendable { case original, translation }

/// Ported from: lib/shared/detail/presentation/detail_providers.dart (`detailTabProvider`, `commentsProvider`,
/// `activityProvider`, `ticketDetailSyncProvider`). The live state of one open ticket: its tab, its DB-backed comments
/// and activity, and whether a provider refresh is running.
@MainActor @Observable
public final class TicketDetailModel {
    public let ticketId: String
    public var tab: DetailTab = .original
    public private(set) var comments: [Comment] = []
    public private(set) var activity: [ActivityEvent] = []
    public private(set) var syncing = false
    private let services: AppServices
    private var tasks: [Task<Void, Never>] = []
    private var refreshing: Task<Void, Never>?

    init(ticketId: String, services: AppServices) { self.ticketId = ticketId; self.services = services }

    /// Starts watching comments / activity and refreshes the ticket from the provider once.
    func start(ticket: Ticket) {
        guard tasks.isEmpty else { return }
        tasks = [
            Task { [weak self, id = ticketId] in
                guard let s = self?.services.comments.watchComments(ticketId: id) else { return }
                for await v in s { self?.comments = v }
            },
            Task { [weak self, id = ticketId] in
                guard let s = self?.services.activity.watchActivity(ticketId: id) else { return }
                for await v in s { self?.activity = v }
            },
        ]
        refresh(ticket)
    }

    func stop() { tasks.forEach { $0.cancel() }; tasks = []; refreshing?.cancel() }

    /// Re-fetches ticket + comments + activity (Flutter `ref.invalidate(ticketDetailSyncProvider)`).
    public func refresh(_ ticket: Ticket) {
        refreshing?.cancel()
        syncing = true
        refreshing = Task { [weak self] in
            guard let self else { return }
            _ = await services.ticketDetail.refresh(ticket: ticket)
            if !Task.isCancelled { syncing = false }
        }
    }

    /// Posts a comment through the provider; true on success (the DB stream then shows it).
    public func postComment(_ ticket: Ticket, body: String) async -> Bool {
        if case .success = await services.ticketDetail.postComment(ticket: ticket, body: body) { return true }
        return false
    }
}
