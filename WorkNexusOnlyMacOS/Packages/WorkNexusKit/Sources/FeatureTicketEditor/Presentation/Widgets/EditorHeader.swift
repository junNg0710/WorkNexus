import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/editor_header.dart
/// The editor's bar: back, what is being edited (and whether its draft is kept), why the last save failed, then the
/// actions at the right edge. `kind` is the ZenTao kind being edited (`bug`, `task`), shown as its icon; `onSave` is
/// nil while the form is not ready to save; `onDiscardDraft` nil hides the action.
struct EditorHeader: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let kind: String
    let onClose: () -> Void
    var onSave: (() -> Void)?
    var saving = false
    var error: String?
    var draftSaved = false
    var draftPicker: AnyView?
    var onDiscardDraft: (() -> Void)?

    var body: some View {
        HStack(spacing: theme.spacing.s12) {
            AppIconButton("arrow.left", help: appString("ticketEditorBack", "Back"), action: onClose)
            ZenTaoKindIcon(kind)
            // Takes the free width, so the actions sit at the bar's right edge.
            HStack(spacing: theme.spacing.s14) {
                Text(title).font(theme.typography.titleSm).foregroundStyle(theme.colors.tx).lineLimit(1)
                if draftSaved { DraftSavedNote() }
                if let draftPicker { draftPicker }
                Spacer(minLength: 0)
            }
            if let error {
                Text(appFormat("ticketEditorSaveFailed", "Couldn't save: %1$@", error)).font(theme.typography.paragraph)
                    .foregroundStyle(theme.colors.red).lineLimit(2).multilineTextAlignment(.trailing).help(error)
            }
            if let onDiscardDraft {
                AppButton(appString("ticketDraftDiscard", "Discard draft"), systemImage: "trash", kind: .ghost, action: onDiscardDraft)
            }
            AppButton(appString("cancel", "Cancel"), action: onClose)
            if saving {
                ProgressView().controlSize(.small).frame(width: theme.sizes.control32)
            } else {
                AppButton(appString("save", "Save"), systemImage: "square.and.arrow.down", kind: .primary) { onSave?() }
                    .disabled(onSave == nil)
            }
        }
        .padding(.horizontal, theme.spacing.s20).padding(.vertical, theme.spacing.s10)
        .background(theme.colors.card)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
    }
}

/// "Draft saved", explaining what is kept on hover.
private struct DraftSavedNote: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.s4) {
            Image(systemName: "checkmark.icloud").font(.system(size: theme.sizes.icon14))
            Text(appString("ticketDraftSaved", "Draft saved")).font(theme.typography.caption)
        }
        .foregroundStyle(theme.colors.tx3)
        .help(appString("ticketDraftSavedHint", "Kept on this device. Files added to it are not kept."))
    }
}
