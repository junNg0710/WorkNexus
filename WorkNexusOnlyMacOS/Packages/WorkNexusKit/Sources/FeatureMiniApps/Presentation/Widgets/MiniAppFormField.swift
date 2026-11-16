import CoreUI
import SwiftUI

/// A labelled text field of the mini app dialog, with an error under it; Enter calls `onSubmit`.
struct MiniAppFormField: View {
    @Environment(\.appTheme) private var theme
    @FocusState private var focused: Bool
    let label: String
    let hint: String
    @Binding var text: String
    var error: String?
    var autofocus = false
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            Text(label).font(theme.typography.metaStrong).foregroundStyle(theme.colors.tx2)
            TextField(hint, text: $text).textFieldStyle(.plain).font(theme.typography.body).foregroundStyle(theme.colors.tx)
                .focused($focused).onSubmit(onSubmit)
                .padding(.horizontal, theme.spacing.s10).frame(height: theme.sizes.control36)
                .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.md)
                    .stroke(error != nil ? theme.colors.red : (focused ? theme.colors.accent : theme.colors.line), lineWidth: theme.borders.hairline))
                .onAppear { if autofocus { focused = true } }
            if let error { AppInlineNote(error, isError: true) }
        }
    }
}
