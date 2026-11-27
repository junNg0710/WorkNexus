import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/app/shell/new_ticket_menu.dart (`NewTicketRailButton`). The rail's accent-filled "+": a menu with a new
/// bug and a new task per ZenTao account, filed into the product / execution the open board shows, then the bugs and
/// tasks left unfinished (`ShellHost.newTicketDrafts`), each to go on with or to discard. The choices come from
/// `ShellHost.newTicketTargets` (the shell knows no tool); the button is hidden without any. ⌘N opens the menu too
/// (`ShellModel.newTicketMenuTick`).
struct NewTicketRailButton: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel
    @State private var open = false
    @State private var anchor = AppMenuAnchor()

    var body: some View {
        let targets = model.host.newTicketTargets?() ?? []
        if !targets.isEmpty {
            let help = appFormat("zentaoNewTicket", "New bug or task (%1$@)", "⌘N")
            VStack(spacing: theme.spacing.s2) {
                Button { AppNativeMenu.popUp(items(), under: anchor) } label: {
                    Image(systemName: "plus").font(.system(size: theme.sizes.icon20, weight: .semibold)).foregroundStyle(theme.colors.accentTx)
                        .frame(width: theme.sizes.control36 + theme.spacing.s8, height: theme.sizes.control36)
                        .background(theme.colors.accent.opacity(open ? 0.8 : 1), in: RoundedRectangle(cornerRadius: theme.radii.lg))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(help)
                .appMenu(anchor, help: help, onOpenChange: { open = $0 }, items: items)
                // A turn later: the menu runs until it is closed, which must not happen inside this update.
                .onChange(of: model.newTicketMenuTick) { _, _ in DispatchQueue.main.async { AppNativeMenu.popUp(items(), under: anchor) } }
                RailDivider()
            }
        }
    }

    /// Read as the menu opens, so it shows the drafts kept by then.
    private func items() -> [AppNativeMenu.Item] {
        let targets = model.host.newTicketTargets?() ?? [], drafts = model.host.newTicketDrafts?() ?? []
        let several = Set(targets.map(\.accountId)).count > 1, nav = model.nav
        return targets.map { t in
            let kind = t.isBug ? appString("newBug", "New bug") : appString("newTask", "New task")
            return AppNativeMenu.Item(several ? appFormat("zentaoNewInAccount", "%1$@ · %2$@", kind, t.accountHandle) : kind,
                                      icon: t.isBug ? "ladybug" : "checkmark.square") { nav.openEditor(t.route) }
        } + drafts.enumerated().map { i, d in
            AppNativeMenu.Item(TicketDraftMenu.named(d.label), icon: d.isBug ? "ladybug" : "checkmark.square", dividerBefore: i == 0,
                               children: TicketDraftMenu.choices(open: { nav.openEditor(d.route) }, discard: d.discard))
        }
    }
}
