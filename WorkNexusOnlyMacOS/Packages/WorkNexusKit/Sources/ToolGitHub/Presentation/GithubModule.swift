import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI

/// Section ids and view modes of the GitHub tool (Dart `GithubPullsSection.modes`, `GithubIssuesSection.modes`).
enum GithubSections {
    static let pulls: SectionID = "github.pulls"
    static let issues: SectionID = "github.issues"
    static let actions: SectionID = "github.actions"

    static func modes(_ kind: GitHubItemKind) -> [ToolViewMode] {
        if kind == .pullRequest {
            return [ToolViewMode(id: "open", label: appString("viewOpen", "Open"), systemImage: "arrow.triangle.pull"),
                    ToolViewMode(id: "merged", label: appString("viewMerged", "Merged"), systemImage: "arrow.triangle.merge"),
                    ToolViewMode(id: "closed", label: appString("viewClosed", "Closed"), systemImage: "xmark.circle"),
                    ToolViewMode(id: "board", label: appString("viewBoard", "Board"), systemImage: "rectangle.split.3x1")]
        }
        return [ToolViewMode(id: "list", label: appString("viewList", "List"), systemImage: "list.bullet"),
                ToolViewMode(id: "board", label: appString("viewBoard", "Board"), systemImage: "rectangle.split.3x1")]
    }
}

/// Ported from: lib/tools/github/github_module.dart
/// The GitHub tool module: sections Pull requests / Issues (Actions is a placeholder), the repository nav pane, boards
/// and lists over the local DB, the PR detail with merge / update-branch / reviewer actions, and the issue / PR header
/// actions. Register it with the shared `ToolRegistry`; it never registers itself (see `init`).
@MainActor
public final class GithubModule: ToolModule {
    let ctx: GithubContext

    /// - Parameters:
    ///   - services: the app's interfaces (tickets, workspaces, settings, comments, activity…).
    ///   - nav: the shell's `AppNavController` (`ShellModel.nav`) — the module's views read and write the location.
    ///   - registry: the registry this module is registered in (`registry.register(module)` after construction); the
    ///     shared board / detail dispatch through it.
    ///   - prService: the optimistic PR / issue service, e.g. `GitHubPrServiceImpl(GitHubPrServiceDependencies(…))`.
    public init(services: AppServices, nav: AppNavController, registry: ToolRegistry, prService: GitHubPrService) {
        ctx = GithubContext(services: services, nav: nav, registry: registry, prService: prService)
    }

    public var providerType: ProviderType { .github }
    public var defaultSection: SectionID { GithubSections.pulls }
    public var roleLabel: String { appString("roleCodeHosting", "Code hosting") }

    public var sections: [ToolSection] {
        [ToolSection(id: GithubSections.pulls, label: appString("githubPullRequests", "Pull Requests"), systemImage: "arrow.triangle.pull",
                     scopeKind: .repository, viewModes: GithubSections.modes(.pullRequest)),
         ToolSection(id: GithubSections.issues, label: appString("githubIssues", "Issues"), systemImage: "smallcircle.filled.circle",
                     scopeKind: .repository, viewModes: GithubSections.modes(.issue)),
         ToolSection(id: GithubSections.actions, label: appString("actions", "Actions"), systemImage: "play", scopeKind: .none, available: false)]
    }

    public func buildNavPane(account: Account, location: ToolLocation) -> AnyView {
        AnyView(GithubNavPane(ctx: ctx, account: account, sections: sections))
    }

    public func buildSection(account: Account, location: ToolLocation) -> AnyView {
        switch location.section {
        case GithubSections.pulls: AnyView(GithubItemsSection(ctx: ctx, account: account, kind: .pullRequest))
        case GithubSections.issues: AnyView(GithubItemsSection(ctx: ctx, account: account, kind: .issue))
        case GithubSections.actions: AnyView(ComingSoonView(systemImage: "play", title: appString("actions", "Actions")))
        default: AnyView(EmptyView())
        }
    }

    public func metrics(account: Account) -> AsyncStream<ToolMetrics?> {
        let stream = ctx.services.tickets.watchTickets(), accountId = account.id
        return AsyncStream { continuation in
            let task = Task {
                for await tickets in stream {
                    let m = ComputeGitHubMetrics()(tickets: tickets, accountId: accountId)
                    continuation.yield(ToolMetrics(primaryCount: m.primaryCount, primaryLabel: appString("githubPullRequests", "Pull Requests"),
                                                   secondaryCount: m.secondaryCount, secondaryLabel: appString("githubIssues", "Issues")))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func scopeTickets(location: ToolLocation, tickets: [Ticket]) -> [Ticket] {
        var accountId: String?
        if case .account(let id) = ctx.nav.state.rail { accountId = id }
        return scopeGitHubTickets(tickets, accountId: accountId, scopeId: location.scopeId)
    }

    public func webURL(account: Account, location: ToolLocation) -> URL? { githubWebURL(account: account, location: location) }

    /// The open repository (`owner/name`) as the scope's title; nil when no repository is open.
    public func scopeTitle(account: Account, location: ToolLocation) -> AsyncStream<String?>? {
        guard let id = location.scopeId else { return nil }
        return AsyncStream { $0.yield(id); $0.finish() }
    }

    // MARK: Detail hooks

    public func buildDetail(ticket: Ticket, onClose: @escaping () -> Void) -> AnyView? {
        guard (ticket.externalType ?? "").lowercased() == "pullrequest", case .githubItem(let entity)? = ticket.providerEntity else { return nil }
        return AnyView(GithubPrDetail(ctx: ctx, ticket: ticket, entity: entity, onClose: onClose).id(ticket.id))
    }

    public func buildActions(ticket: Ticket) -> AnyView? { AnyView(GithubActions(ctx: ctx, ticket: ticket)) }

    public func buildDetailSidebar(ticket: Ticket) -> AnyView? {
        guard case .githubItem(let entity)? = ticket.providerEntity else { return nil }
        return AnyView(GithubDetailSections(ctx: ctx, ticket: ticket, entity: entity))
    }
}

/// The page of the provider the current section maps to (Dart `GithubModule.webUrl`): the repo's, else the account's
/// dashboard (`/pulls`, `/issues`); the base URL defaults to github.com.
func githubWebURL(account: Account, location: ToolLocation) -> URL? {
    let raw = account.baseUrl ?? ""
    let base = raw.isEmpty ? "https://github.com" : raw
    let root = base.hasSuffix("/") ? String(base.dropLast()) : base
    let page = location.section == GithubSections.issues ? "issues" : "pulls"
    if let scope = location.scopeId { return URL(string: "\(root)/\(scope)/\(page)") }
    return URL(string: "\(root)/\(page)")
}
