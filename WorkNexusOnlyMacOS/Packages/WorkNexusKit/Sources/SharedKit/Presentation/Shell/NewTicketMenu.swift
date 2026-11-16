import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/app/shell/new_ticket_menu.dart (`NewTicketRailButton`). The rail's accent-filled "+": a menu with a new
/// bug and a new task per ZenTao account, filed into the product / execution the open board shows. The choices come from
/// `ShellHost.newTicketTargets` (the shell knows no tool); the button is hidden without any. ⌘N opens the menu too
/// (`ShellModel.newTicketMenuTick`).
struct NewTicketRailButton: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel
    @State private var open = false

    var body: some View {
        let targets = model.host.newTicketTargets?() ?? []
        if !targets.isEmpty {
            let several = Set(targets.map(\.accountId)).count > 1
            VStack(spacing: theme.spacing.s2) {
                Button { open.toggle() } label: {
                    Image(systemName: "plus").font(.system(size: theme.sizes.icon20, weight: .semibold)).foregroundStyle(theme.colors.accentTx)
                        .frame(width: theme.sizes.control36 + theme.spacing.s8, height: theme.sizes.control36)
                        .background(theme.colors.accent.opacity(open ? 0.8 : 1), in: RoundedRectangle(cornerRadius: theme.radii.lg))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(appFormat("zentaoNewTicket", "New bug or task (%1$@)", "⌘N"))
                .popover(isPresented: $open, arrowEdge: .trailing) {
                    AppMenuPanel(entries: targets.map { entry(for: $0, several: several) }) { i in
                        open = false
                        model.nav.openEditor(targets[i].route)
                    }
                    .environment(\.appTheme, theme)
                }
                .onChange(of: model.newTicketMenuTick) { _, _ in open = true }
                RailDivider()
            }
        }
    }

    private func entry(for t: NewTicketTarget, several: Bool) -> AppMenuEntry {
        let kind = t.isBug ? appString("newBug", "New bug") : appString("newTask", "New task")
        return AppMenuEntry(icon: t.isBug ? "ladybug" : "checkmark.square",
                            label: several ? appFormat("zentaoNewInAccount", "%1$@ · %2$@", kind, t.accountHandle) : kind)
    }
}
