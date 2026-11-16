import CoreDomain
import CoreTools
import CoreUI
import Foundation
import Observation
import SharedKit

/// Ported from: lib/shared/detail/presentation/detail_providers.dart (`commentsProvider`, `activityProvider`,
/// `ticketDetailSyncProvider`) as the PR detail uses them: the DB-backed comments / activity of one PR and a manual
/// provider refresh (the shared panel already refreshes once when the ticket opens).
@MainActor @Observable
final class GithubPrDetailModel {
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

/// The state actions of a PR that ask for confirmation first (merge and close cannot be taken back from the app).
enum GithubPrConfirm: Equatable {
    case merge, close, updateBranch

    var destructive: Bool { self == .close }

    func title(_ key: String) -> String {
        switch self {
        case .merge: appFormat("githubConfirmMergeTitle", "Merge #%1$@?", key)
        case .close: appFormat("githubConfirmCloseTitle", "Close #%1$@?", key)
        case .updateBranch: appFormat("githubConfirmUpdateTitle", "Update branch of #%1$@?", key)
        }
    }

    func message(head: String?, base: String?) -> String {
        switch self {
        case .merge: appFormat("githubConfirmMergeBody", "This merges %1$@ into %2$@ and cannot be undone from here.",
                               head ?? "the branch", base ?? "the base branch")
        case .close: appString("githubConfirmCloseBody", "The pull request will be closed without merging. You can reopen it later.")
        case .updateBranch: appString("githubConfirmUpdateBody", "The base branch is merged into the pull request's branch.")
        }
    }

    var confirmLabel: String {
        switch self {
        case .merge: appString("githubMerge", "Merge")
        case .close: appString("close", "Close")
        case .updateBranch: appString("updateBranch", "Update branch")
        }
    }
}

extension GithubPrConfirm {
    var command: GithubPrCommand {
        switch self { case .merge: .merge; case .close: .close; case .updateBranch: .updateBranch }
    }
}
