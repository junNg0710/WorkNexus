/// Ported from: lib/features/chat/presentation/widgets/send_code_dialog.dart + chat_send_code_button.dart
import CoreUI
import SwiftUI

/// Sheet to send a code snippet (`SendCodeMessage`): optional name, language and the code itself.
struct SendCodeDialog: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let controller: ChatComposerController
    @State private var code = ""
    @State private var name = ""
    @State private var language = SendCodeMessage.plainText
    @State private var error: String?
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s12) {
            Text(appString("chatSendCode", "Send code")).font(theme.typography.titleSm).foregroundStyle(theme.colors.tx)
            HStack(spacing: theme.spacing.s10) {
                TextField(appString("chatCodeName", "Code name"), text: $name).textFieldStyle(.roundedBorder)
                Picker(appString("chatCodeLanguage", "Language"), selection: $language) {
                    ForEach(SendCodeMessage.languages, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 180)
            }
            TextEditor(text: $code)
                .font(theme.typography.mono)
                .scrollContentBackground(.hidden)
                .padding(theme.spacing.s8)
                .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .frame(minHeight: 220)
            Text(appString("chatCodeHint", "Enter the code to send, up to {max} characters").replacingOccurrences(of: "{max}", with: "\(SendCodeMessage.maxLength)"))
                .font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
            if let error { Text(error).font(theme.typography.meta).foregroundStyle(theme.colors.red) }
            HStack {
                Spacer()
                AppButton(appString("chatCancel", "Cancel")) { dismiss() }
                AppButton(appString("chatSend", "Send"), kind: .primary) { send() }
            }
        }
        .padding(theme.spacing.s20)
        .frame(width: theme.sizes.dialogLg)
        .background(theme.colors.card)
        .environment(\.appTheme, theme)
    }

    private func send() {
        guard !sending else { return }
        sending = true
        Task {
            let r = await controller.sendCode(code, language: language, name: name)
            sending = false
            switch r {
            case .success: dismiss(); controller.model.requestFocus()
            case .failure(let f): error = f.message
            }
        }
    }
}
