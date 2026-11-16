/// Ported from: lib/tools/zentao/presentation/detail/zentao_bug_action_dialog.dart
import CoreDomain
import CoreUI
import SwiftUI

/// Confirms, closes or reopens a ZenTao bug, asking what ZenTao's own form does: who it goes to next, the build it
/// shows up in again (activate), and a note. Resolve has its own dialog (`ZentaoResolveDialog`).
struct ZentaoBugActionDialog: View {
    @Environment(\.toasts) private var toasts
    let deps: ZentaoDependencies; let state: ZentaoUIState; let ticket: Ticket; let action: ZenTaoBugAction; let onClose: () -> Void
    @State private var note: ZentaoNoteModel
    @State private var build = "trunk"
    @State private var assignee: String?
    @State private var busy = false

    init(deps: ZentaoDependencies, state: ZentaoUIState, ticket: Ticket, action: ZenTaoBugAction, onClose: @escaping () -> Void) {
        precondition(action != .resolve, "Resolve has its own dialog")
        self.deps = deps; self.state = state; self.ticket = ticket; self.action = action; self.onClose = onClose
        _note = State(initialValue: ZentaoNoteModel(ticket: ticket))
    }

    private func submit(_ label: String) {
        busy = true
        let comment = note.value, assignee = assignee, build = build, t = ticket, wf = deps.workflow, action = action
        Task {
            let ok = await ZentaoActionRunner.run(state: state, ticket: t, toasts: toasts, label: label) {
                switch action {
                case .confirm: await wf.confirmBug(t, assignee: assignee, comment: comment)
                case .activate: await wf.activateBug(t, build: build, assignee: assignee, comment: comment)
                case .close: await wf.closeBug(t, comment: comment)
                case .resolve: .failure(.unexpected("Resolve has its own dialog"))
                }
            }
            _ = ok
            onClose()
        }
    }

    var body: some View {
        let look = ZentaoActionLooks.bug(action)
        ZentaoActionFrame(title: ZentaoActionLooks.title(look.label, ticket.externalKey), icon: look.icon, submitLabel: look.label,
                          busy: busy, onSubmit: { submit(look.label) }, onClose: onClose) {
            if action == .activate {
                ZentaoFieldLabel(appString("zentaoBuild", "Build"))
                ZentaoTextInput(text: $build)
                ZentaoFieldGap()
            }
            if action != .close {
                ZentaoFieldLabel(appString("zentaoAssignToOptional", "Assign to (optional)"))
                ZentaoAssigneeDropdown(deps: deps, ticket: ticket, value: assignee) { assignee = $0 }
                ZentaoFieldGap()
            }
            ZentaoFieldLabel(appString("zentaoNote", "Note"))
            ZentaoNoteField(deps: deps, ticket: ticket, note: note)
        }
    }
}

/// A single-line themed text input for an action dialog.
struct ZentaoTextInput: View {
    @Environment(\.appTheme) private var theme
    @Binding var text: String
    var onSubmit: (() -> Void)?
    var body: some View {
        TextField("", text: $text).textFieldStyle(.plain).font(theme.typography.body).foregroundStyle(theme.colors.tx)
            .onSubmit { onSubmit?() }
            .padding(.horizontal, theme.spacing.s10).frame(height: theme.sizes.control32)
            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}
