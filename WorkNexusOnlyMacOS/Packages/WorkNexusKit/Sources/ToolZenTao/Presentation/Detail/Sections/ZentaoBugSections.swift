/// Ported from: lib/tools/zentao/presentation/detail/{bug_detail_sections,bug_module_name}.dart
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// The ZenTao bug's typed metadata as two region cards: what the bug *is* (classification) and how it *moved*
/// (lifecycle). Empty classification fields collapse behind a "Show N empty fields" toggle; empty lifecycle rows are
/// always hidden.
public struct ZentaoBugSections: View {
    @Environment(\.appTheme) private var theme
    let deps: ZentaoDependencies; let state: ZentaoUIState; let bug: ZenTaoBugEntity; let ticket: Ticket
    @State private var showEmpty = false
    @State private var dateFormat = "iso"

    public init(deps: ZentaoDependencies, state: ZentaoUIState, bug: ZenTaoBugEntity, ticket: Ticket) {
        self.deps = deps; self.state = state; self.bug = bug; self.ticket = ticket
    }

    public var body: some View {
        let rows = ZentaoBugSectionRows(bug: bug, ticket: ticket, dateFormat: dateFormat)
        let reopened = bug.activatedCount ?? 0
        VStack(alignment: .leading, spacing: theme.spacing.s14) {
            DetailFieldsCard(title: appString("classification", "Classification"), rows: rows.filled, valueViews: valueViews(reopened)) {
                if showEmpty && !rows.empty.isEmpty {
                    DetailFieldRows(rows: rows.empty, labelWidth: DetailFieldsCard<EmptyView>.labelWidth, alignEnd: true)
                }
                if !rows.empty.isEmpty {
                    EmptyFieldsToggle(count: rows.empty.count, expanded: showEmpty) { showEmpty.toggle() }
                }
            }
            if !rows.lifecycle.isEmpty { DetailFieldsCard(title: appString("lifecycle", "Lifecycle"), rows: rows.lifecycle) }
        }
        .zentaoDateFormat(deps, into: $dateFormat)
    }

    /// Severity and priority as the same chips as the header; links for module, execution, story and task.
    private func valueViews(_ reopened: Int) -> [String: AnyView] {
        var v: [String: AnyView] = [
            appString("status", "Status"): AnyView(TicketStatusPill(ticket: ticket, registry: deps.registry())),
        ]
        if let s = bug.severity { v[appString("fieldSeverity", "Severity")] = AnyView(SeverityTag(s)) }
        if hasExplicitPriority(ticket) { v[appString("priority", "Priority")] = AnyView(PriorityTag(ticket.providerType, ticket.priority)) }
        // A bug that keeps coming back is worth noticing.
        v[appString("fieldReopened", "Reopened")] = AnyView(ZentaoReopenedText(count: reopened))
        if let module = zentaoLinkId(bug.module), let product = zentaoLinkId(bug.product) {
            v[appString("fieldModule", "Module")] = AnyView(ZentaoBugModuleName(deps: deps, accountId: ticket.accountId, productId: product, moduleId: module))
        }
        if let id = zentaoLinkId(bug.execution) {
            let e = ProviderExecution(id: id, name: zentaoNameOr(bug.executionName, id), projectId: zentaoLinkId(bug.project) ?? "0", accountId: ticket.accountId)
            v[appString("fieldExecution", "Execution")] = AnyView(ZentaoExecutionLink(deps: deps, state: state, execution: e))
        }
        if let id = zentaoLinkId(bug.story) {
            v[appString("fieldStory", "Story")] = AnyView(ZentaoLinkedTicket(deps: deps, ticket: ticket, type: "story", id: id,
                                                                            label: zentaoJoined([bug.storyTitle, "#\(id)"])))
        }
        if let id = zentaoLinkId(bug.task) {
            v[appString("task", "Task")] = AnyView(ZentaoLinkedTicket(deps: deps, ticket: ticket, type: "task", id: id,
                                                                     label: zentaoJoined([bug.taskName, "#\(id)"])))
        }
        return v
    }
}

private struct ZentaoReopenedText: View {
    @Environment(\.appTheme) private var theme
    let count: Int
    var body: some View {
        Text(appFormat("reopenedTimes", "Reopened ×%1$@", "\(count)")).font(theme.typography.paragraph).foregroundStyle(theme.colors.amber)
    }
}

/// A bug's module by its path ("Livestream/Share"). ZenTao gives the bug only the module id, so the id shows until the
/// product's module names load, and stays when they cannot.
struct ZentaoBugModuleName: View {
    @Environment(\.appTheme) private var theme
    let deps: ZentaoDependencies; let accountId: String; let productId: String; let moduleId: String
    @State private var names: [String: String] = [:]

    var body: some View {
        Text(names[moduleId] ?? moduleId).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx).multilineTextAlignment(.trailing)
            .task(id: "\(accountId):\(productId)") { names = await ZentaoModuleNames.bugModules(deps, accountId: accountId, productId: productId) }
    }
}

/// A product's bug modules as id -> path, fetched once per product per run (the list costs a whole form page); a
/// failed fetch is not kept, so reopening the bug retries it.
@MainActor
enum ZentaoModuleNames {
    private static var cache: [String: [String: String]] = [:]

    static func bugModules(_ deps: ZentaoDependencies, accountId: String, productId: String) async -> [String: String] {
        let key = "\(accountId):\(productId)"
        if let hit = cache[key] { return hit }
        guard case .success(let list) = await deps.editor.bugModules(accountId: accountId, productId: productId) else { return [:] }
        let names = Dictionary(list.map { ($0.value, $0.label.hasPrefix("/") ? String($0.label.dropFirst()) : $0.label) }, uniquingKeysWith: { a, _ in a })
        cache[key] = names
        return names
    }
}
