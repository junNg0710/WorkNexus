import CoreDomain
import CoreTools
import CoreUI
import Foundation
import Observation
import SharedKit

/// Ported from: lib/shared/detail/presentation/detail_providers.dart (`commentsProvider`, `activityProvider`,
/// `ticketDetailSyncProvider`) as the MR detail uses them: the DB-backed comments / activity of one MR and a manual
/// provider refresh (the shared panel already refreshes once when the ticket opens).
@MainActor @Observable
final class GitlabMrDetailModel {
    let ticketId: String
    private(set) var comments: [Comment] = []
    private(set) var activity: [ActivityEvent] = []
    private(set) var syncing = false
    private let services: AppServices
    private var refreshing: Task<Void, Never>?

    init(ticketId: String, services: AppServices) { self.ticketId = ticketId; self.services = services }

    /// Watches comments and activity until cancelled (run it from `.task`).
    func run() async {
        let comments = services.comments.watchComments(ticketId: ticketId)
        let activity = services.activity.watchActivity(ticketId: ticketId)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in for await v in comments { self?.comments = v } }
            group.addTask { @MainActor [weak self] in for await v in activity { self?.activity = v } }
        }
    }

    /// Re-fetches ticket + comments + activity from the provider.
    func refresh(_ ticket: Ticket) {
        refreshing?.cancel()
        syncing = true
        let detail = services.ticketDetail
        refreshing = Task { [weak self] in
            _ = await detail.refresh(ticket: ticket)
            if !Task.isCancelled { self?.syncing = false }
        }
    }
}
