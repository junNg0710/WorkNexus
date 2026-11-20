/// Ported from: lib/tools/zentao/zentao_module.dart
import CoreDomain
import CoreTools
import CoreUI
import Foundation
import Observation
import SharedKit
import SwiftUI

/// The ZenTao tool as the shell hosts it: sections Tasks / Bugs / Docs, the nav pane, the boards, the detail hooks,
/// the action dialogs and the docs reader (Flutter `ZentaoModule`).
///
/// ### Wiring (composition root)
/// ```swift
/// let wiring = ZentaoModuleData.wire(db: db, sync: coordinator, workspaces: ..., tickets: ..., credentials: ...)
/// let workflow = ZentaoModuleData.workflow(sync: coordinator, workspaces: ..., runner: ...)
/// let module = ZentaoModule(ZentaoDependencies(wiring: wiring, workflow: workflow, services: services, nav: nav,
///                                              registry: { registry }))
/// let registry = ToolRegistry([module, ...])
/// ```
/// The shell's `ToolPaneHost` / viewport then call `buildNavPane` / `buildSection`; `DetailPanel` calls the detail
/// hooks. To get the translation dot on cards and the chat photo in person chips, inject `\.ticketCardAccessory`,
/// `\.personAvatar` and `\.personChip` on the view tree (see `SharedKit/BoardEnvironment.swift`); without them the
/// cards show no dot and a plain initial avatar.
@MainActor
public final class ZentaoModule: ToolModule {
    public let dependencies: ZentaoDependencies
    private var cachedState: ZentaoUIState?
    private var cachedDocs: ZentaoDocsState?
    private var cachedDetail: ZentaoDetailHooks?

    public init(_ dependencies: ZentaoDependencies) { self.dependencies = dependencies }

    /// For tests: a module over an existing session state.
    init(_ dependencies: ZentaoDependencies, state: ZentaoUIState) { self.dependencies = dependencies; cachedState = state }

    /// The session state (selection, boards, loaders); created on first use because it needs the finished registry.
    public var state: ZentaoUIState {
        if let s = cachedState { return s }
        let s = ZentaoUIState(deps: dependencies)
        s.start()
        cachedState = s
        return s
    }
    var docsState: ZentaoDocsState {
        if let d = cachedDocs { return d }
        let d = ZentaoDocsState(deps: dependencies); cachedDocs = d; return d
    }
    private var detail: ZentaoDetailHooks {
        if let d = cachedDetail { return d }
        let d = ZentaoDetailHooks(deps: dependencies, state: state); cachedDetail = d; return d
    }

    // MARK: ToolModule

    public var providerType: ProviderType { .zentao }
    public var defaultSection: SectionID { ZentaoSection.tasks }
    public var sectionsOnRail: Bool { true }
    public var roleLabel: String { appString("roleProjectManagement", "Project management") }

    public var sections: [ToolSection] {
        let modes = [ToolViewMode(id: "board", label: "viewBoard", systemImage: "rectangle.split.3x1"),
                     ToolViewMode(id: "list", label: "viewList", systemImage: "list.bullet")]
        return [
            ToolSection(id: ZentaoSection.tasks, label: "tasks", systemImage: "checklist", scopeKind: .project, viewModes: modes),
            ToolSection(id: ZentaoSection.bugs, label: "bugs", systemImage: "ladybug", scopeKind: .product, viewModes: modes),
            ToolSection(id: ZentaoSection.docs, label: "docs", systemImage: "book", scopeKind: .library),
        ]
    }

    public func buildNavPane(account: Account, location: ToolLocation) -> AnyView {
        let docs = AnyView(ZentaoDocLibsPane(deps: dependencies, docs: docsState, account: account, location: location))
        return AnyView(ZentaoNavPane(deps: dependencies, state: state, account: account, location: location,
                                     sections: sections, docsPane: docs))
    }

    public func buildSection(account: Account, location: ToolLocation) -> AnyView {
        switch location.section {
        case ZentaoSection.tasks: AnyView(ZentaoTasksSection(deps: dependencies, state: state, account: account, location: location))
        case ZentaoSection.bugs: AnyView(ZentaoBugsSection(deps: dependencies, state: state, account: account, location: location))
        case ZentaoSection.docs: AnyView(ZentaoDocsSection(deps: dependencies, docs: docsState, account: account, location: location))
        default: AnyView(EmptyView())
        }
    }

    /// The open tasks / bugs assigned to the account's user (reads only the local DB).
    public func metrics(account: Account) -> AsyncStream<ToolMetrics?> {
        let tickets = dependencies.services.tickets.watchTickets()
        return AsyncStream { out in
            // Off the main thread: every ticket write re-counts the whole table, which made the app stutter wherever the
            // user was (scrolling a chat) while a sync ran.
            let task = Task.detached(priority: .utility) {
                for await list in tickets { out.yield(ComputeZentaoMetrics()(tickets: list, account: account)) }
                out.finish()
            }
            out.onTermination = { _ in task.cancel() }
        }
    }

    public func scopeTickets(location: ToolLocation, tickets: [Ticket]) -> [Ticket] {
        switch location.section {
        case ZentaoSection.tasks: state.scopeTasks(tickets)
        case ZentaoSection.bugs: state.scopeBugs(tickets)
        default: tickets
        }
    }

    /// Docs' libraries tree folds away, so a document can take the width.
    public func paneCollapsible(location: ToolLocation) -> Bool { true }

    public func webURL(account: Account, location: ToolLocation) -> URL? {
        guard let base = account.baseUrl, !base.isEmpty else { return nil }
        let root = base.hasSuffix("/") ? String(base.dropLast()) : base
        if location.section == ZentaoSection.docs { return URL(string: "\(root)/doc-index.html") }
        let bugs = location.section == ZentaoSection.bugs
        if let scope = location.scopeId { return URL(string: bugs ? "\(root)/product-browse-\(scope).html" : "\(root)/project-task-\(scope).html") }
        return URL(string: bugs ? "\(root)/product.html" : "\(root)/project.html")
    }

    /// The name of what the location is scoped to (a product, an execution) for the title bar's breadcrumb.
    public func scopeTitle(account: Account, location: ToolLocation) -> AsyncStream<String?>? {
        let bugs = location.section == ZentaoSection.bugs
        guard bugs || location.section == ZentaoSection.tasks else { return nil }
        let state = self.state, accountId = account.id, scopeId = location.scopeId
        let (stream, out) = AsyncStream<String?>.makeStream()
        let task = Task { @MainActor in
            while !Task.isCancelled {
                await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
                    let title = withObservationTracking { state.scopeTitle(accountId: accountId, scopeId: scopeId, bugs: bugs) }
                        onChange: { resume.resume() }
                    out.yield(title)
                }
            }
            out.finish()
        }
        out.onTermination = { _ in task.cancel() }
        return stream
    }

    // MARK: Detail hooks (ZenTao uses the standard tabbed panel; `buildDetail` stays nil)

    public func buildActions(ticket: Ticket) -> AnyView? { detail.actions(ticket) }
    public func buildDetailHeaderExtras(ticket: Ticket) -> AnyView? { detail.headerExtras(ticket) }
    public func buildStatusStrip(ticket: Ticket) -> AnyView? { detail.statusStrip(ticket) }
    public func buildDetailEffort(ticket: Ticket) -> AnyView? { detail.effort(ticket) }
    public func buildDetailSubtasks(ticket: Ticket) -> AnyView? { detail.subtasks(ticket) }
    public func buildDetailAttachments(ticket: Ticket) -> AnyView? { detail.attachments(ticket) }
    public func buildDetailSidebar(ticket: Ticket) -> AnyView? { detail.sidebar(ticket) }
}
