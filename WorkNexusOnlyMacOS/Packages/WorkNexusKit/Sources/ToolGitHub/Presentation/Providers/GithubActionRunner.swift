import CoreDomain
import CoreUI
import Foundation

/// Ported from: lib/tools/github/presentation/providers/github_detail_providers.dart + the `_run` helpers of
/// github_pr_detail.dart / github_ticket_actions.dart. Runs a PR state command through its use case and words the toast.
enum GithubPrCommand { case merge, updateBranch, close, reopen }

struct GithubActionRunner {
    let service: GitHubPrService

    func perform(_ command: GithubPrCommand, _ ticket: Ticket) async -> Outcome<Void> {
        switch command {
        case .merge: await MergeGitHubPr(service)(ticket)
        case .updateBranch: await UpdateGitHubPrBranch(service)(ticket)
        case .close: await CloseGitHubItem(service)(ticket)
        case .reopen: await ReopenGitHubItem(service)(ticket)
        }
    }

    func successMessage(_ command: GithubPrCommand, _ ticket: Ticket) -> String {
        let key = ticket.externalKey
        switch command {
        case .merge: return appFormat("githubPrMerged", "Merged #%1$@", key)
        case .updateBranch: return appFormat("githubPrBranchUpdated", "Updated branch for #%1$@", key)
        case .close: return appFormat("githubItemClosed", "Closed #%1$@", key)
        case .reopen: return appFormat("githubItemReopened", "Reopened #%1$@", key)
        }
    }

    static func failureMessage(_ f: Failure, fallback: String? = nil) -> String {
        appFormat("actionFailed", "Failed: %1$@", f.message.isEmpty ? (fallback ?? appString("providerActionFailed", "Provider action failed")) : f.message)
    }
}
