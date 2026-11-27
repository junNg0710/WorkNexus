/// Not in the Flutter app (its "New bug" / "New task" buttons only opened an empty editor).
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// The primary "New bug" / "New task" button of a section. With bugs (tasks) of this account left unfinished it says how
/// many and opens a menu: a new one, or each draft to go on with or to discard, and all of them deleted at once (asked
/// first). Without any it opens the editor at once.
struct ZentaoNewTicketButton: View {
    @Environment(\.toasts) private var toasts
    let deps: ZentaoDependencies; let state: ZentaoUIState; let account: Account; let bugs: Bool
    @State private var kept = KeptTicketDrafts()
    @State private var anchor = AppMenuAnchor()
    @State private var confirmDeleteAll = false

    private var drafts: [ZenTaoSavedDraft] { kept.drafts(accountId: account.id, isBug: bugs) }
    private var title: String { bugs ? appString("newBug", "New bug") : appString("newTask", "New task") }

    /// Filed into the open product / execution (what the board is scoped to), else ZenTao's current one.
    private func create() {
        deps.nav.openEditor(bugs ? state.newBugRoute(accountId: account.id) : state.newTaskRoute(accountId: account.id))
    }

    private func menu() -> [AppNativeMenu.Item] {
        [AppNativeMenu.Item(title, icon: "plus", action: create)]
            + TicketDraftMenu.items(drafts, named: true, dividerBefore: true, open: { deps.nav.openEditor(KeptTicketDrafts.route($0)) },
                                    discard: { delete([$0]) }, discardAll: { confirmDeleteAll = true })
    }

    private func delete(_ gone: [ZenTaoSavedDraft]) {
        guard let stored = deps.services.zentaoDrafts else { return }
        Task { if let f = await KeptTicketDrafts.discard(gone, from: stored) { toasts?.show(f.message, kind: .error) } }
    }

    var body: some View {
        let count = drafts.count
        let help = bugs ? appString("tipNewBug", "File a new bug in the open product") : appString("tipNewTask", "Create a new task in the open execution")
        Group {
            if count == 0 {
                AppButton(title, systemImage: "plus", kind: .primary, action: create).help(help)
            } else {
                // The keyboard presses the button; the mouse opens the menu from the AppKit view over it (`appMenu`).
                AppButton("\(title) · \(appFormat("ticketDrafts", "Drafts (%1$@)", "\(count)"))", systemImage: "plus", kind: .primary) {
                    AppNativeMenu.popUp(menu(), under: anchor)
                }
                .appMenu(anchor, help: help, items: menu)
            }
        }
        .task { if let stored = deps.services.zentaoDrafts { await kept.run(stored) } }
        .appConfirmDialog(isPresented: $confirmDeleteAll, title: appFormat("ticketDraftsDeleteAllTitle", "Delete all %1$@ drafts?", "\(count)"),
                          message: appString("ticketDraftDiscardMessage", "What you wrote will be deleted."),
                          confirmLabel: appString("ticketDraftsDeleteAll", "Delete all drafts"), destructive: true) { delete(drafts) }
    }
}
