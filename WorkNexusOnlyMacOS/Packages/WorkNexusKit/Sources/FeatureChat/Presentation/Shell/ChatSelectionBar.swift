/// Not in the Flutter app.
import AppKit
import CoreUI
import SwiftUI

/// What "Multiple select" puts in the composer's place: how many messages are picked and what to do with them together
/// — copy them as one text, forward them, or start a ZenTao bug / task / todo quoting them all.
struct ChatSelectionBar: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let state: ChatThreadState

    var body: some View {
        let picked = state.selectedInOrder
        let forwardable = picked.filter(ForwardChatMessage(model.repository).canForward)
        HStack(spacing: theme.spacing.s8) {
            AppIconButton("xmark", help: shellString("chatCancel", "Cancel")) { state.endSelection() }
                .keyboardShortcut(.cancelAction)
            Text(L.selected(picked.count)).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
            Spacer(minLength: theme.spacing.s8)
            AppButton(L.copy, systemImage: "doc.on.doc", kind: .ghost) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ChatMessageExport.transcript(picked, users: state.users), forType: .string)
                model.toasts.show(L.copied)
                state.endSelection()
            }
            .disabled(picked.isEmpty)
            AppButton(L.forward, systemImage: "arrowshape.turn.up.right", kind: .ghost) {
                model.forwardRequest = ChatForwardRequest(messages: forwardable, onDone: { state.endSelection() })
            }
            .disabled(forwardable.isEmpty)
            if let open = model.events.onCreateTicket {
                SelectionCreateMenu(disabled: picked.isEmpty) { kind in
                    open(ChatTicketRequest(kind: kind, accountId: model.accountId, seed: ChatMessageExport.seed(picked, state: state)))
                    state.endSelection()
                }
            }
        }
        .padding(.horizontal, theme.spacing.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.panel)
        .overlay(alignment: .top) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
    }
}

/// "Create…": a bug, a task or a todo from the picked messages.
private struct SelectionCreateMenu: View {
    @Environment(\.appTheme) private var theme
    let disabled: Bool
    let create: (ChatTicketKind) -> Void

    var body: some View {
        Menu {
            Button { create(.bug) } label: { Label(L.createBug, systemImage: "ladybug") }
            Button { create(.task) } label: { Label(L.createTask, systemImage: "checklist") }
            Button { create(.todo) } label: { Label(L.createTodo, systemImage: "calendar.badge.plus") }
        } label: {
            Label(shellString("chatCreateFrom", "Create…"), systemImage: "plus.circle").font(theme.typography.bodyStrong)
        }
        .menuStyle(.button).buttonStyle(.plain).fixedSize().foregroundStyle(theme.colors.tx).disabled(disabled)
    }
}
