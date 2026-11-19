/// Ported from: lib/tools/zentao/presentation/detail/zentao_ticket_actions.dart
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// What the ZenTao toolbar offers on a ticket, as data: Assign, the one main status action, and the rest in "⋯".
/// A story offers Assign only.
struct ZentaoActionsModel {
    enum Item: Hashable { case bug(ZenTaoBugAction), task(ZenTaoTaskAction), create(ZenTaoCreateAction) }

    let canAssign: Bool
    let primary: Item?
    let more: [Item]
    /// The direct "Clone task" button of a task.
    let cloneTask: Bool

    init(_ ticket: Ticket) {
        let kind = zentaoKind(ticket)
        let bug = kind == "bug" ? ListZenTaoBugActions()(ticket) : nil
        let task = kind == "task" ? ListZenTaoTaskActions()(ticket) : nil
        canAssign = bug?.canAssign ?? task?.canAssign ?? true
        primary = bug?.primary.map(Item.bug) ?? task?.primary.map(Item.task)
        var rest: [Item] = []
        for a in bug?.actions ?? [] where a != bug?.primary { rest.append(.bug(a)) }
        for a in task?.actions ?? [] where a != task?.primary { rest.append(.task(a)) }
        for a in ListZenTaoCreateActions()(ticket) { rest.append(.create(a)) }
        more = rest
        cloneTask = kind == "task"
    }

    static func look(_ item: Item) -> ZentaoActionLook {
        switch item {
        case .bug(let a): ZentaoActionLooks.bug(a)
        case .task(let a): ZentaoActionLooks.task(a)
        case .create(let a): ZentaoActionLooks.create(a)
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

/// ZenTao's own toolbar for a bug or task: Assign, a "⋯" menu, and the one status action that moves the ticket on as
/// the filled main button. The other status actions ZenTao allows, and what can be started from the ticket (a copy, a
/// subtask, a bug), wait in the menu.
public struct ZentaoTicketActions: View {
    @Environment(\.appTheme) private var theme
    let deps: ZentaoDependencies; let state: ZentaoUIState; let ticket: Ticket
    @State private var dialog: ZentaoDialog?

    public init(deps: ZentaoDependencies, state: ZentaoUIState, ticket: Ticket) {
        self.deps = deps; self.state = state; self.ticket = ticket
    }

    private func run(_ item: ZentaoActionsModel.Item) {
        switch item {
        case .bug(let a): dialog = a == .resolve ? .resolve : .bug(a)
        case .task(let a): dialog = .task(a)
        case .create(let a): deps.nav.openEditor(zentaoEditorRoute(for: a, ticket: ticket))
        }
    }

    public var body: some View {
        let model = ZentaoActionsModel(ticket)
        FlowLayout(spacing: theme.spacing.s8, rowSpacing: theme.spacing.s8) {
            if model.canAssign {
                ZentaoActionButton(look: ZentaoActionLook(label: appString("assign", "Assign"), icon: "person.badge.plus")) {
                    dialog = .assign
                }
            }
            if model.cloneTask {
                ZentaoActionButton(look: ZentaoActionLooks.create(.copyTask)) { run(.create(.copyTask)) }
            }
            if !model.more.isEmpty {
                ZentaoMoreMenu(items: model.more.filter { $0 != .create(.copyTask) }, onPick: run)
            }
            if let primary = model.primary {
                let look = ZentaoActionsModel.look(primary)
                AppButton(look.label, systemImage: look.icon, kind: .primary) { run(primary) }
            }
        }
        .sheet(item: $dialog) { d in
            ZentaoDialogHost(deps: deps, state: state, ticket: ticket, dialog: d) { dialog = nil }
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

/// The "⋯" button holding the actions that are not the main one.
struct ZentaoMoreMenu: View {
    @Environment(\.appTheme) private var theme
    let items: [ZentaoActionsModel.Item]; let onPick: (ZentaoActionsModel.Item) -> Void
    var body: some View {
        AppMenuButton(help: appString("more", "More"), items: {
            items.map { item in
                let look = ZentaoActionsModel.look(item)
                return AppNativeMenu.Item(look.label, icon: look.icon) { onPick(item) }
            }
        }) {
            Image(systemName: "ellipsis").font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.tx)
                .frame(width: theme.sizes.control32, height: theme.sizes.control32)
                .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        }
        .fixedSize()
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
