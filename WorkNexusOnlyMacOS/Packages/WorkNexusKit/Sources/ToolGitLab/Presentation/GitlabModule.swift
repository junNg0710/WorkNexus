import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI

/// Section ids and view modes of the GitLab tool (Dart `GitlabMrsSection.modes`, `GitlabIssuesSection.modes`).
enum GitlabSections {
    static let mrs: SectionID = "gitlab.mrs"
    static let issues: SectionID = "gitlab.issues"
    static let pipelines: SectionID = "gitlab.pipelines"

    static func modes(_ kind: GitLabItemKind) -> [ToolViewMode] {
        if kind == .mergeRequest {
            return [ToolViewMode(id: "open", label: appString("viewOpen", "Open"), systemImage: "arrow.triangle.pull"),
                    ToolViewMode(id: "merged", label: appString("viewMerged", "Merged"), systemImage: "arrow.triangle.merge"),
                    ToolViewMode(id: "closed", label: appString("viewClosed", "Closed"), systemImage: "xmark.circle"),
                    ToolViewMode(id: "board", label: appString("viewBoard", "Board"), systemImage: "rectangle.split.3x1")]
        }
        return [ToolViewMode(id: "list", label: appString("viewList", "List"), systemImage: "list.bullet"),
                ToolViewMode(id: "board", label: appString("viewBoard", "Board"), systemImage: "rectangle.split.3x1")]
    }
}

/// Ported from: lib/tools/gitlab/gitlab_module.dart
/// The GitLab tool module: sections Merge Requests / Issues (Pipelines is a placeholder), the project tree nav pane,
/// boards and lists over the local DB, the merge-request detail with approve / merge / rebase / draft actions and the
/// metadata editors, and the issue / MR header actions. Register it with the shared `ToolRegistry`; it never registers
/// itself (see `init`).
@MainActor
public final class GitlabModule: ToolModule {
    let ctx: GitlabContext

    /// - Parameters:
    ///   - services: the app's interfaces (tickets, workspaces, settings, comments, activity…).
    ///   - nav: the shell's `AppNavController` (`ShellModel.nav`) — the module's views read and write the location.
    ///   - registry: the registry this module is registered in (`registry.register(module)` after construction); the
    ///     shared board / detail dispatch through it.
    ///   - mrService: the optimistic MR / issue service, e.g. `GitLabMrServiceImpl(GitLabMrServiceDependencies(…))`.
    public init(services: AppServices, nav: AppNavController, registry: ToolRegistry, mrService: GitLabMrService) {
        ctx = GitlabContext(services: services, nav: nav, registry: registry, mrService: mrService)
    }

    public var providerType: ProviderType { .gitlab }
    public var defaultSection: SectionID { GitlabSections.mrs }
    public var roleLabel: String { appString("roleCodeHostingCi", "Code hosting & CI") }

    public var sections: [ToolSection] {
        [ToolSection(id: GitlabSections.mrs, label: appString("gitlabMergeRequests", "Merge Requests"), systemImage: "arrow.triangle.pull",
                     scopeKind: .repository, viewModes: GitlabSections.modes(.mergeRequest)),
         ToolSection(id: GitlabSections.issues, label: appString("gitlabIssues", "Issues"), systemImage: "smallcircle.filled.circle",
                     scopeKind: .repository, viewModes: GitlabSections.modes(.issue)),
         ToolSection(id: GitlabSections.pipelines, label: appString("pipelines", "Pipelines"), systemImage: "play", scopeKind: .none, available: false)]
    }

    public func buildNavPane(account: Account, location: ToolLocation) -> AnyView {
        AnyView(GitlabNavPane(ctx: ctx, account: account, sections: sections))
    }

    public func buildSection(account: Account, location: ToolLocation) -> AnyView {
        switch location.section {
        case GitlabSections.mrs: AnyView(GitlabItemsSection(ctx: ctx, account: account, kind: .mergeRequest))
        case GitlabSections.issues: AnyView(GitlabItemsSection(ctx: ctx, account: account, kind: .issue))
        case GitlabSections.pipelines: AnyView(ComingSoonView(systemImage: "play", title: appString("pipelines", "Pipelines")))
        default: AnyView(EmptyView())
        }
    }

    public func scopeTickets(location: ToolLocation, tickets: [Ticket]) -> [Ticket] {
        var accountId: String?
        if case .account(let id) = ctx.nav.state.rail { accountId = id }
        return scopeGitLabTickets(tickets, accountId: accountId, scopeId: location.scopeId)
    }

    public func webURL(account: Account, location: ToolLocation) -> URL? { gitlabWebURL(account: account, location: location) }

    /// The open project's name as the scope's title (its id until the project list is known); nil off a project.
    public func scopeTitle(account: Account, location: ToolLocation) -> AsyncStream<String?>? {
        guard let id = location.scopeId else { return nil }
        let model = ctx.projects(for: account.id)
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                continuation.yield(model.projects.first { $0.id == id }?.name ?? id)
                await model.load()
                if let name = model.projects.first(where: { $0.id == id })?.name { continuation.yield(name) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
