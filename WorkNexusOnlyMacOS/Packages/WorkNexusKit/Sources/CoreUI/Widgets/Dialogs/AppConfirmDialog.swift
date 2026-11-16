import SwiftUI

/// Ported from: lib/core/widgets/app_confirm_dialog.dart
/// Asks before an action that can't be undone. `destructive` paints the confirm button red (delete, remove,
/// discard). Cancel, Esc and the close button all dismiss without confirming.
public struct AppConfirmDialog: View {
    @Environment(\.appTheme) private var theme
    let title: String; let message: String; let confirmLabel: String?; let destructive: Bool
    let onConfirm: () -> Void; let onCancel: () -> Void

    public init(title: String, message: String, confirmLabel: String? = nil, destructive: Bool = false,
                onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.title = title; self.message = message; self.confirmLabel = confirmLabel; self.destructive = destructive
        self.onConfirm = onConfirm; self.onCancel = onCancel
    }

    public var body: some View {
        AppDialogFrame(title: title, maxWidth: theme.sizes.dialogSm, onClose: onCancel) {
            Text(message).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s24)
        } actions: {
            Spacer(minLength: 0)
            AppButton(appString("cancel", "Cancel"), kind: .ghost, action: onCancel)
            AppButton(confirmLabel ?? (destructive ? appString("confirmDelete", "Delete") : appString("confirm", "Confirm")),
                      kind: destructive ? .danger : .primary, action: onConfirm)
        }
    }
}

public extension View {
    /// Shows an `AppConfirmDialog` while `isPresented`; `onConfirm` runs only when the person confirms, before the dialog closes.
    func appConfirmDialog(isPresented: Binding<Bool>, title: String, message: String, confirmLabel: String? = nil,
                          destructive: Bool = false, onConfirm: @escaping () -> Void) -> some View {
        appDialog(isPresented: isPresented) {
            AppConfirmDialog(title: title, message: message, confirmLabel: confirmLabel, destructive: destructive,
                             onConfirm: { AppConfirmFlow.confirm(isPresented: isPresented, action: onConfirm) },
                             onCancel: { isPresented.wrappedValue = false })
        }
    }
}

/// What confirming does. The action runs BEFORE the dialog is dismissed: callers read the state that drives `isPresented`
/// (the item being removed), and dismissing clears it — dismiss-first made every "Remove" a silent no-op.
enum AppConfirmFlow {
    static func confirm(isPresented: Binding<Bool>, action: () -> Void) {
        action()
        isPresented.wrappedValue = false
    }
}
