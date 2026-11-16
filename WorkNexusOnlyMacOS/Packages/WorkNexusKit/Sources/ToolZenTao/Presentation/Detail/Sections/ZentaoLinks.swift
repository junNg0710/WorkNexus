/// Ported from: detail/{zentao_execution_link,zentao_linked_ticket,parent_task_link}.dart, util/open_zentao_task.dart
import CoreDomain
import CoreUI
import SwiftUI

/// An accent text link in a sidebar table; `busy` shows a spinner after it.
struct ZentaoFieldLink: View {
    @Environment(\.appTheme) private var theme
    @State private var hovered = false
    let label: String; var busy = false; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: theme.spacing.s4) {
                Text(label).font(theme.typography.paragraph).foregroundStyle(theme.colors.accent).underline(hovered, color: theme.colors.accent)
                    .multilineTextAlignment(.trailing)
                if busy { ProgressView().controlSize(.mini) }
            }
        }
        .buttonStyle(.plain).onHover { hovered = $0 }.disabled(busy)
    }
}

/// The execution a ticket belongs to, as a link that opens that execution's task board (closing the detail panel),
/// the way the sidebar does.
struct ZentaoExecutionLink: View {
    let deps: ZentaoDependencies; let state: ZentaoUIState; let execution: ProviderExecution
    var body: some View {
        ZentaoFieldLink(label: execution.name) {
            deps.nav.closeTicket()
            state.openExecution(execution)
        }
    }
}

/// A ZenTao story, task or bug a ticket links to, as an accent link: tapping it opens that ticket in the detail
/// panel, fetched from ZenTao first when it has not been synced.
struct ZentaoLinkedTicket: View {
    @Environment(\.toasts) private var toasts
    let deps: ZentaoDependencies; let ticket: Ticket; let type: String; let id: String; let label: String
    @State private var opening = false

    var body: some View {
        ZentaoFieldLink(label: label, busy: opening) {
            opening = true
            Task {
                let r = await deps.openLinked(from: ticket, type: type, id: id)
                opening = false
                if case .failure(let f) = r { toasts?.show(appFormat("actionFailed", "Failed: %1$@", f.message), kind: .error) }
            }
        }
    }
}

/// A subtask's parent, shown by its title: tapping it opens the parent in the detail panel, fetched from ZenTao first
/// when it has not been synced.
public struct ZentaoParentTaskLink: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let deps: ZentaoDependencies; let ticket: Ticket; let parentId: String; let parentName: String?
    @State private var opening = false
    @State private var syncedName: String?

    public init(deps: ZentaoDependencies, ticket: Ticket, parentId: String, parentName: String? = nil) {
        self.deps = deps; self.ticket = ticket; self.parentId = parentId; self.parentName = parentName
    }

    public var body: some View {
        let c = theme.colors
        let name = parentName ?? syncedName
        Button {
            opening = true
            Task {
                let r = await deps.openLinked(from: ticket, type: "task", id: parentId)
                opening = false
                if case .failure(let f) = r { toasts?.show(appFormat("actionFailed", "Failed: %1$@", f.message), kind: .error) }
            }
        } label: {
            HStack(spacing: theme.spacing.s6) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: theme.sizes.icon16)).foregroundStyle(c.accent)
                Text(appString("parentTask", "Parent task")).font(theme.typography.meta).foregroundStyle(c.tx2)
                Text("#\(parentId)").font(theme.typography.mono).foregroundStyle(c.accent)
                if let name { Text(name).font(theme.typography.metaStrong).foregroundStyle(c.accent).lineLimit(1) }
                if opening { ProgressView().controlSize(.mini) }
                else { Image(systemName: "chevron.right").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.accent) }
            }
            .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s4)
            .background(c.sel, in: RoundedRectangle(cornerRadius: theme.radii.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(opening).pointerStyle(.link)
        .task(id: parentId) {
            guard parentName == nil else { return }
            if case .success(let t) = await deps.services.tickets.ticket(id: zenTaoTicketId(accountId: ticket.accountId, type: "task", id: parentId)) { syncedName = t?.title }
        }
    }
}
