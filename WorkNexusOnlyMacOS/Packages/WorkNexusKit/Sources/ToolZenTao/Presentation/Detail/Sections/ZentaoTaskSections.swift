/// Ported from: lib/tools/zentao/presentation/detail/task_detail_sections.dart
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// A ZenTao task's metadata as region cards, like a bug's and ZenTao's own task view: what the task is and where it
/// sits (classification), the bugs reported against it, its hours and dates (effort), and how it moved (lifecycle).
public struct ZentaoTaskSections: View {
    @Environment(\.appTheme) private var theme
    let deps: ZentaoDependencies; let state: ZentaoUIState; let task: ZenTaoTaskEntity; let ticket: Ticket
    @State private var dateFormat = "iso"
    @State private var syncedParentName: String?
    @State private var bugs = ZentaoTaskBugsModel()

    public init(deps: ZentaoDependencies, state: ZentaoUIState, task: ZenTaoTaskEntity, ticket: Ticket) {
        self.deps = deps; self.state = state; self.task = task; self.ticket = ticket
    }

    public var body: some View {
        // A subtask's parent: its name as ZenTao gave it, else as synced here.
        let parentName = task.parentName ?? syncedParentName
        let rows = ZentaoTaskSectionRows(task: task, ticket: ticket, parentName: parentName, dateFormat: dateFormat)
        VStack(alignment: .leading, spacing: theme.spacing.s14) {
            DetailFieldsCard(title: appString("classification", "Classification"), rows: rows.classification,
                             valueViews: valueViews(parentName: parentName))
            ZentaoTaskBugsCard(deps: deps, ticket: ticket, model: bugs)
            if !rows.effort.isEmpty { DetailFieldsCard(title: appString("taskEffort", "Effort"), rows: rows.effort) }
            if !rows.lifecycle.isEmpty { DetailFieldsCard(title: appString("lifecycle", "Lifecycle"), rows: rows.lifecycle) }
        }
        .zentaoDateFormat(deps, into: $dateFormat)
        .task(id: ticket.id) { bugs.start(deps, ticket: ticket) }
        .onDisappear { bugs.stop() }
        .task(id: task.parentId) {
            guard task.parentName == nil, let pid = task.parentId else { return }
            let id = zenTaoTicketId(accountId: ticket.accountId, type: "task", id: pid)
            if case .success(let t) = await deps.services.tickets.ticket(id: id) { syncedParentName = t?.title }
        }
    }

    private func linked(_ name: String?, _ id: String) -> String {
        [name, "#\(id)"].compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " · ")
    }

    private func valueViews(parentName: String?) -> [String: AnyView] {
        var v: [String: AnyView] = [
            appString("status", "Status"): AnyView(TicketStatusPill(ticket: ticket, registry: deps.registry())),
        ]
        if hasExplicitPriority(ticket) { v[appString("priority", "Priority")] = AnyView(PriorityTag(ticket.providerType, ticket.priority)) }
        if let id = task.execution {
            let e = ProviderExecution(id: id, name: task.executionName ?? id, projectId: task.project ?? "0", accountId: ticket.accountId)
            v[appString("fieldExecution", "Execution")] = AnyView(ZentaoExecutionLink(deps: deps, state: state, execution: e))
        }
        if let id = task.parentId {
            v[appString("parentTask", "Parent task")] = AnyView(ZentaoLinkedTicket(deps: deps, ticket: ticket, type: "task", id: id, label: linked(parentName, id)))
        }
        if let id = task.story {
            v[appString("fieldStory", "Story")] = AnyView(ZentaoLinkedTicket(deps: deps, ticket: ticket, type: "story", id: id, label: linked(task.storyTitle, id)))
        }
        if let id = task.fromBug {
            v[appString("fieldFromBug", "From bug")] = AnyView(ZentaoLinkedTicket(deps: deps, ticket: ticket, type: "bug", id: id, label: "#\(id)"))
        }
        return v
    }
}
