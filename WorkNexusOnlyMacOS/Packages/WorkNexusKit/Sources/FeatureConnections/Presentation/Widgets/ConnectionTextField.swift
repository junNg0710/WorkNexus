import CoreUI
import SwiftUI

/// Ported from: lib/core/widgets/connection_text_field.dart
/// A labeled text field in the app's input style; `trailing` sits at the end of the label row (e.g. the
/// "Generate token" link). `secure` hides what is typed.
struct ConnectionTextField<Trailing: View>: View {
    @Environment(\.appTheme) private var theme
    @FocusState private var focused: Bool
    let label: String
    @Binding var text: String
    var hint: String = ""
    var secure = false
    var autofocus = false
    var onSubmit: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            HStack(spacing: 0) {
                Text(label).font(theme.typography.label).foregroundStyle(theme.colors.tx2)
                Spacer(minLength: 0)
                trailing
            }
            Group {
                if secure { SecureField(hint, text: $text) } else { TextField(hint, text: $text) }
            }
            .textFieldStyle(.plain).font(theme.typography.body).foregroundStyle(theme.colors.tx)
            .focused($focused).onSubmit { onSubmit?() }
            .padding(.horizontal, theme.spacing.s10)
            .frame(height: theme.sizes.control36)
            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md)
                .stroke(focused ? theme.colors.accent : theme.colors.line, lineWidth: theme.borders.hairline))
            .onAppear { if autofocus { focused = true } }
        }
    }
}

extension ConnectionTextField where Trailing == EmptyView {
    init(label: String, text: Binding<String>, hint: String = "", secure: Bool = false, autofocus: Bool = false,
         onSubmit: (() -> Void)? = nil) {
        self.init(label: label, text: text, hint: hint, secure: secure, autofocus: autofocus, onSubmit: onSubmit, trailing: { EmptyView() })
    }
}

/// Ported from: lib/features/connections/presentation/widgets/generate_token_link.dart
/// A subtle "Generate token" link beside a PAT field's label; `action` opens the provider's token-creation page.
struct GenerateTokenLink: View {
    @Environment(\.appTheme) private var theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.s2) {
                Image(systemName: "arrow.up.right.square").font(.system(size: theme.sizes.icon12))
                Text(L.generateToken).font(theme.typography.label)
            }
            .foregroundStyle(theme.colors.accent)
            .padding(.horizontal, theme.spacing.s6)
            .frame(minHeight: theme.sizes.control32 - theme.spacing.s8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerStyle(.link)
    }
}
