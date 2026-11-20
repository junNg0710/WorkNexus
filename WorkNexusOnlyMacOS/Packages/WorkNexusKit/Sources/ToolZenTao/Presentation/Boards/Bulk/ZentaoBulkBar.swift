/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

enum ZentaoBulkDialog: Identifiable, Hashable {
    case assign, priority, close, failures
    var id: Int { switch self { case .assign: 0; case .priority: 1; case .close: 2; case .failures: 3 } }
}

/// The bar over the board's foot while tickets are picked: how many, and what to do to all of them. Esc clears the pick.
struct ZentaoBulkBar: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let deps: ZentaoDependencies; let state: ZentaoUIState; let bugs: Bool
    @State private var model = ZentaoBulkModel()
    @State private var dialog: ZentaoBulkDialog?
    /// The person a one-click assign was for, when it needs the dialog to ask for hours left first.
    @State private var presetLogin: String?

    private var board: BoardController { bugs ? state.bugBoard : state.taskBoard }
    /// While picking (even before the first pick) or a run goes on.
    private var showing: Bool { board.isSelecting || !board.selectedIds.isEmpty || model.progress != nil }

    var body: some View {
        let targets = state.bulkTargets(bugs: bugs)
        Group {
            if showing {
                HStack(spacing: theme.spacing.s8) {
                    // One line each, whatever the board's width.
                    if let p = model.progress { ZentaoBulkRunning(progress: p, onStop: model.stop) }
                    else { actions(targets) }
                }
                .fixedSize()
                .padding(.horizontal, theme.spacing.s14).padding(.vertical, theme.spacing.s8)
                .appGlass(in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                .padding(.bottom, theme.spacing.s20)
                .background {
                    // Present only while picking, so it never takes Esc from a field.
                    Button("") { board.endSelecting() }.keyboardShortcut(.escape, modifiers: []).opacity(0).frame(width: 0, height: 0)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(showing)
        .animation(.easeOut(duration: 0.15), value: showing)
        .appDialog(item: $dialog) { which in
            switch which {
            case .assign: ZentaoBulkAssignDialog(deps: deps, state: state, bugs: bugs, model: model, initialLogin: presetLogin,
                                                 onClose: { dialog = nil; presetLogin = nil })
            case .priority: ZentaoBulkPriorityDialog(state: state, bugs: bugs, model: model, onClose: { dialog = nil })
            case .close: ZentaoBulkCloseDialog(state: state, bugs: bugs, model: model, onClose: { dialog = nil })
            case .failures: ZentaoBulkFailuresDialog(state: state, bugs: bugs, model: model, onClose: { dialog = nil })
            }
        }
        .onChange(of: model.failures == nil) { _, none in if !none { dialog = .failures } }
        .onChange(of: state.bulkDrop) { _, drop in
            guard let drop, drop.bugs == bugs else { return }
            state.bulkDrop = nil
            let tickets = state.shownTickets(bugs: bugs).filter { drop.ids.contains($0.id) }
            Task {
                guard await model.quickAssign(drop.login, tickets: tickets, state: state, bugs: bugs, toasts: toasts) == .needsHours else { return }
                // The dialog works on the pick: the dropped cards become it.
                board.select(tickets.map(\.id))
                askHours(drop.login)
            }
        }
        .onChange(of: state.bulkRequest) { _, request in
            guard let request, request.bugs == bugs else { return }
            dialog = request.dialog
            state.bulkRequest = nil
        }
    }

    /// Some tasks have no hours left: the dialog opens on `login`, asking for them.
    private func askHours(_ login: String) {
        presetLogin = login
        dialog = .assign
    }

    @ViewBuilder private func actions(_ targets: [Ticket]) -> some View {
        Text(appFormat("leaderSelected", "%1$@ selected", "\(targets.count)")).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
        Divider().frame(height: theme.sizes.icon14)
        ZentaoQuickAssignButton(state: state, enabled: !targets.isEmpty, onPick: { login in
            Task { if await model.quickAssign(login, tickets: targets, state: state, bugs: bugs, toasts: toasts) == .needsHours { askHours(login) } }
        }, onOther: { dialog = .assign })
        AppButton(appString("priority", "Priority"), systemImage: "flag", kind: .ghost) { dialog = .priority }.disabled(targets.isEmpty)
            .help(appString("tipBulkPriority", "Set the priority of every selected ticket"))
        AppButton(appString("leaderBulkCloseName", "Close"), systemImage: "checkmark.circle", kind: .ghost) { dialog = .close }.disabled(targets.isEmpty)
            .help(appString("tipBulkClose", "Close the selected tickets ZenTao lets be closed (a resolved bug, a finished or cancelled task); the others are skipped"))
        Divider().frame(height: theme.sizes.icon14)
        AppButton(appString("leaderSelectAll", "Select all shown"), kind: .ghost) { state.selectAllShown(bugs: bugs) }
            .help(appString("tipBulkSelectAll", "Select every ticket the board shows now"))
        AppButton(appString("leaderClearSelection", "Clear"), kind: .ghost) { board.clearSelection() }
            .help(appString("tipBulkClear", "Drop the selection (Esc)"))
    }
}

private struct ZentaoBulkRunning: View {
    @Environment(\.appTheme) private var theme
    let progress: ZentaoBulkModel.Progress; let onStop: () -> Void
    var body: some View {
        ProgressView().controlSize(.small)
        Text(appFormat("leaderBulkRunning", "%1$@ of %2$@", "\(progress.done)", "\(progress.total)")).font(theme.typography.bodyStrong)
            .foregroundStyle(theme.colors.tx)
        AppButton(appString("leaderBulkStop", "Stop"), kind: .ghost, action: onStop)
            .help(appString("tipBulkStop", "Stop after the ticket being changed; the rest stay as they are"))
    }
}
