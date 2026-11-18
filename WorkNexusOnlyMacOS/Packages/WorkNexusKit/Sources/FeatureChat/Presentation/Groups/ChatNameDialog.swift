import CoreUI
import SwiftUI

/// Asks for a name — a group's, a category's — and saves it with `onSave`, closing once that succeeds (a failure is shown
/// by the shell's toast and the dialog stays). `extra` sits under the field and gets the name being typed (e.g. names to
/// pick from).
/// Ported from: lib/features/chat/presentation/widgets/chat_name_dialog.dart
struct ChatNameDialog<Extra: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let hint: String
    let onSave: (String) async -> Bool
    let onClose: () -> Void
    let extra: (Binding<String>) -> Extra
    @State private var name: String
    @State private var saving = false
    @FocusState private var focused: Bool

    init(title: String, initial: String, hint: String, onSave: @escaping (String) async -> Bool, onClose: @escaping () -> Void,
         @ViewBuilder extra: @escaping (Binding<String>) -> Extra) {
        self.title = title; self.hint = hint; self.onSave = onSave; self.onClose = onClose; self.extra = extra
        _name = State(initialValue: initial)
    }

    private var blank: Bool { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        AppDialogFrame(title: title, maxWidth: theme.sizes.dialogSm, onClose: onClose) {
            VStack(alignment: .leading, spacing: 0) {
                TextField(hint, text: $name).textFieldStyle(.roundedBorder).focused($focused).onSubmit(save)
                extra($name)
            }
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s24)
        } actions: {
            Spacer(minLength: 0)
            AppButton(shellString("chatCancel", "Cancel"), kind: .ghost, action: onClose)
            AppButton(shellString("chatSave", "Save"), kind: .primary, action: save).disabled(blank || saving)
        }
        .onAppear { focused = true }
    }

    private func save() {
        guard !saving, !blank else { return }
        saving = true
        Task {
            let ok = await onSave(name)
            saving = false
            if ok { onClose() }
        }
    }
}

extension ChatNameDialog where Extra == EmptyView {
    init(title: String, initial: String, hint: String, onSave: @escaping (String) async -> Bool, onClose: @escaping () -> Void) {
        self.init(title: title, initial: initial, hint: hint, onSave: onSave, onClose: onClose) { _ in EmptyView() }
    }
}
