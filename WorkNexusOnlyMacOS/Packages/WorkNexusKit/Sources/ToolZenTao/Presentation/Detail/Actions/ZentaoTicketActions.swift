/// Ported from: lib/tools/zentao/presentation/detail/zentao_ticket_actions.dart
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// What the ZenTao toolbar offers on a ticket, as data, laid out as ZenTao's own toolbar is: the labelled actions
/// (a bug's Confirm, Assign, Resolve, Convert to Task; a task's Child Task, Assign, Start, Finish, Cancel, Report bug -
/// each only while ZenTao allows it), then Edit, Copy and Delete as icons. A story offers Assign only.
///
/// Every action is a button of its own: none waits in a "more" menu, where it took a second click to reach.
struct ZentaoActionsModel {
    enum Item: Hashable { case assign, bug(ZenTaoBugAction), task(ZenTaoTaskAction), create(ZenTaoCreateAction), edit, delete }

    /// The labelled buttons, in ZenTao's order.
    let buttons: [Item]
    /// The one of them that moves the ticket on: drawn filled.
    let primary: Item?
    /// The icon buttons after them: edit, copy, delete.
    let tools: [Item]

    var canAssign: Bool { buttons.contains(.assign) }

    /// A task's status actions, as ZenTao's toolbar orders them.
    private static let taskOrder: [ZenTaoTaskAction] = [.start, .restart, .pause, .finish, .cancel, .close, .activate]

    init(_ ticket: Ticket) {
        let kind = zentaoKind(ticket)
        let creates = ListZenTaoCreateActions()(ticket)
        var buttons: [Item] = []
        switch kind {
        case "bug":
            let menu = ListZenTaoBugActions()(ticket)
            if menu.actions.contains(.confirm) { buttons.append(.bug(.confirm)) }
            if menu.canAssign { buttons.append(.assign) }
            buttons += menu.actions.filter { $0 != .confirm }.map(Item.bug)
            if creates.contains(.taskFromBug) { buttons.append(.create(.taskFromBug)) }
            primary = menu.primary.map(Item.bug)
            tools = [.edit, .create(.copyBug), .delete]
        case "task":
            let menu = ListZenTaoTaskActions()(ticket)
            if creates.contains(.subtask) { buttons.append(.create(.subtask)) }
            if menu.canAssign { buttons.append(.assign) }
            buttons += Self.taskOrder.filter(menu.actions.contains).map(Item.task)
            if creates.contains(.bugFromTask) { buttons.append(.create(.bugFromTask)) }
            primary = menu.primary.map(Item.task)
            tools = [.edit, .create(.copyTask), .delete]
        default:
            buttons = [.assign]
            primary = nil
            tools = []
        }
        self.buttons = buttons
    }

    static func look(_ item: Item) -> ZentaoActionLook {
        switch item {
        case .assign: ZentaoActionLooks.assign
        case .bug(let a): ZentaoActionLooks.bug(a)
        case .task(let a): ZentaoActionLooks.task(a)
        case .create(let a): ZentaoActionLooks.create(a)
        case .edit: ZentaoActionLooks.edit
        case .delete: ZentaoActionLooks.delete
        }
    }
}

/// The dialogs the toolbar opens.
enum ZentaoDialog: Identifiable {
    case bug(ZenTaoBugAction), resolve, task(ZenTaoTaskAction), assign
    var id: String {
        switch self { case .bug(let a): "bug.\(a)"; case .resolve: "resolve"; case .task(let a): "task.\(a)"; case .assign: "assign" }
    }
}

/// ZenTao's own toolbar for a bug or task (`ZentaoActionsModel`): each action a button, the one that moves the ticket
/// on filled; Edit, Copy and Delete as icons; deleting asks first.
public struct ZentaoTicketActions: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let deps: ZentaoDependencies; let state: ZentaoUIState; let ticket: Ticket
    @State private var dialog: ZentaoDialog?
    @State private var confirmingDelete = false

    public init(deps: ZentaoDependencies, state: ZentaoUIState, ticket: Ticket) {
        self.deps = deps; self.state = state; self.ticket = ticket
    }

    private func run(_ item: ZentaoActionsModel.Item) {
        switch item {
        case .assign: dialog = .assign
        case .bug(let a): dialog = a == .resolve ? .resolve : .bug(a)
        case .task(let a): dialog = .task(a)
        case .create(let a):
            // A task made from a bug starts with the bug's title, as ZenTao's own form does.
            let prefill = a == .taskFromBug ? TicketEditorPrefill(title: ticket.title, bodyHtml: "") : nil
            deps.nav.openEditor(zentaoEditorRoute(for: a, ticket: ticket), prefill: prefill)
        case .edit:
            deps.nav.openEditor(zentaoKind(ticket) == "bug" ? .editBug(accountId: ticket.accountId, ticketId: ticket.id)
                                                            : .editTask(accountId: ticket.accountId, ticketId: ticket.id))
        case .delete: confirmingDelete = true
        }
    }

    private func delete() {
        let ticket = ticket, nav = deps.nav
        let remove = DeleteZenTaoTicket(workflow: deps.workflow, tickets: deps.services.tickets)
        Task {
            let deleted = await ZentaoActionRunner.run(
                state: state, ticket: ticket, toasts: toasts, label: ZentaoActionLooks.delete.label,
                successMessage: appFormat("zentaoTicketDeleted", "Deleted #%1$@", ticket.externalKey)) { await remove(ticket) }
            // Its panel has nothing left to show - unless the reader has gone on to another ticket meanwhile.
            if deleted, nav.ticketHistories[nav.rail.key]?.last == ticket.id { nav.closeTicket() }
        }
    }

    public var body: some View {
        let model = ZentaoActionsModel(ticket)
        // One line whenever it can be: with every label; else with the "start something new" actions (a subtask, a bug,
        // a task from the bug) as icons; and only when even that is too wide, wrapped.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: theme.spacing.s8) { ZentaoActionItems(model: model, compact: false, run: run) }
            HStack(spacing: theme.spacing.s8) { ZentaoActionItems(model: model, compact: true, run: run) }
            FlowLayout(spacing: theme.spacing.s8, rowSpacing: theme.spacing.s8) {
                ZentaoActionItems(model: model, compact: true, run: run)
            }
        }
        .sheet(item: $dialog) { d in
            ZentaoDialogHost(deps: deps, state: state, ticket: ticket, dialog: d) { dialog = nil }
        }
        .appConfirmDialog(isPresented: $confirmingDelete,
                          title: appFormat("zentaoDeleteTicketTitle", "Delete #%1$@?", ticket.externalKey),
                          message: appFormat("zentaoDeleteTicketMessage",
                                             "“%1$@” is removed from ZenTao for everyone. An administrator can bring it back from ZenTao’s recycle bin.",
                                             ticket.title),
                          destructive: true) { delete() }
    }
}

/// The bar's buttons, in order: the labelled actions (the one that moves the ticket on filled), a hairline, then Edit,
/// Copy and Delete as icons. `compact` draws the create actions as icons too, their name in the tooltip.
struct ZentaoActionItems: View {
    @Environment(\.appTheme) private var theme
    let model: ZentaoActionsModel
    let compact: Bool
    let run: (ZentaoActionsModel.Item) -> Void

    var body: some View {
        ForEach(model.buttons, id: \.self) { item in
            let look = ZentaoActionsModel.look(item)
            if item == model.primary {
                AppButton(look.label, systemImage: look.icon, kind: .primary) { run(item) }
            } else if compact, case .create = item {
                AppIconButton(look.icon, help: look.label, outlined: true) { run(item) }
            } else {
                ZentaoActionButton(look: look) { run(item) }
            }
        }
        if !model.tools.isEmpty {
            Rectangle().fill(theme.colors.line2).frame(width: theme.borders.hairline, height: theme.sizes.icon16)
                .padding(.horizontal, theme.spacing.s2)
        }
        ForEach(model.tools, id: \.self) { item in
            let look = ZentaoActionsModel.look(item)
            AppIconButton(look.icon, help: look.label, outlined: true) { run(item) }
        }
    }
}

/// An outlined icon + label button of the action bar.
struct ZentaoActionButton: View {
    @Environment(\.appTheme) private var theme
    let look: ZentaoActionLook; let action: () -> Void
    var body: some View {
        AppButton(look.label, systemImage: look.icon, action: action)
    }
}

/// Picks the dialog view for a toolbar choice.
struct ZentaoDialogHost: View {
    let deps: ZentaoDependencies; let state: ZentaoUIState; let ticket: Ticket; let dialog: ZentaoDialog; let onClose: () -> Void
    var body: some View {
        switch dialog {
        case .bug(let a): ZentaoBugActionDialog(deps: deps, state: state, ticket: ticket, action: a, onClose: onClose)
        case .resolve: ZentaoResolveDialog(deps: deps, state: state, ticket: ticket, onClose: onClose)
        case .task(let a): ZentaoTaskActionDialog(deps: deps, state: state, ticket: ticket, action: a, onClose: onClose)
        case .assign:
            if zentaoKind(ticket) == "task" { ZentaoTaskAssignDialog(deps: deps, state: state, ticket: ticket, onClose: onClose) }
            else { ZentaoAssignDialog(deps: deps, state: state, ticket: ticket, onClose: onClose) }
        }
    }
}
