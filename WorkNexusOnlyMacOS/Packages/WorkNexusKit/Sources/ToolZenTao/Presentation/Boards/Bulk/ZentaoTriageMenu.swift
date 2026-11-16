/// Not in the Flutter app: triage from a card or a row's right-click menu, without opening the ticket.
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

private struct ZentaoStateKey: EnvironmentKey { static let defaultValue: ZentaoUIState? = nil }

extension EnvironmentValues {
    /// The ZenTao tool's session state, for the parts of a card or row that act on the board (a ticket's triage menu).
    var zentaoState: ZentaoUIState? {
        get { self[ZentaoStateKey.self] }
        set { self[ZentaoStateKey.self] = newValue }
    }
}

/// A bulk dialog asked for from outside the bar (a card's menu); the bar of the matching board opens it.
struct ZentaoBulkRequest: Hashable { var bugs: Bool; var dialog: ZentaoBulkDialog }

/// Pick this ticket, assign it, or set its priority: the ticket joins the pick and the bulk dialog opens for it - and for
/// the others already picked, which is what a leader who ⌘-clicked a few cards and right-clicked one means.
@MainActor
struct ZentaoTriageMenu {
    let state: ZentaoUIState; let ticket: Ticket

    private var bugs: Bool { zentaoKind(ticket) == "bug" }
    private var board: BoardController { bugs ? state.bugBoard : state.taskBoard }
    private var picked: Bool { board.selectedIds.contains(ticket.id) }

    /// The entries and what each does, in the order they are drawn.
    private var items: [(entry: AppMenuEntry, run: () -> Void)] {
        let canAssign = bugs ? ListZenTaoBugActions()(ticket).canAssign : ListZenTaoTaskActions()(ticket).canAssign
        var out: [(AppMenuEntry, () -> Void)] = [
            (AppMenuEntry(icon: picked ? "checkmark.circle.fill" : "checkmark.circle",
                          label: picked ? appString("leaderDeselect", "Remove from selection") : appString("leaderSelect", "Select"),
                          dividerBefore: true), { board.toggleSelected(ticket.id) }),
        ]
        if canAssign { out.append((AppMenuEntry(icon: "person.badge.plus", label: appString("leaderBulkAssign", "Assign…")), { ask(.assign) })) }
        if zentaoIsOpen(ticket) { out.append((AppMenuEntry(icon: "flag", label: appString("leaderBulkPriority", "Priority…")), { ask(.priority) })) }
        return out
    }

    var entries: [AppMenuEntry] { items.map(\.entry) }

    func run(_ index: Int) {
        let items = items
        if items.indices.contains(index) { items[index].run() }
    }

    private func ask(_ dialog: ZentaoBulkDialog) {
        if !picked { board.select([ticket.id]) }
        state.bulkRequest = ZentaoBulkRequest(bugs: bugs, dialog: dialog)
    }
}
