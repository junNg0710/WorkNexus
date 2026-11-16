import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/editor_inputs.dart
/// A one-line text input that reports each change; its text is set once, from `initial`. `numeric` accepts hours
/// (digits and one decimal point) only; `big` is the title's larger text.
struct EditorTextInput: View {
    @Environment(\.appTheme) private var theme
    @State private var text: String
    let hint: String
    let numeric: Bool
    let big: Bool
    let onChanged: (String) -> Void

    init(initial: String, hint: String = "", numeric: Bool = false, big: Bool = false, onChanged: @escaping (String) -> Void) {
        _text = State(initialValue: initial)
        self.hint = hint; self.numeric = numeric; self.big = big; self.onChanged = onChanged
    }

    var body: some View {
        TextField(hint, text: $text)
            .textFieldStyle(.plain)
            .font(big ? theme.typography.bodyStrong : theme.typography.paragraph)
            .foregroundStyle(theme.colors.tx)
            .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s8)
            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
            .onChange(of: text) { _, new in
                if numeric {
                    let cleaned = Self.hoursOnly(new)
                    if cleaned != new { text = cleaned; return }
                }
                onChanged(new)
            }
    }

    /// Digits and at most one decimal point.
    static func hoursOnly(_ s: String) -> String {
        var seenDot = false
        return String(s.filter { c in
            if c.isASCII, c.isNumber { return true }
            if c == ".", !seenDot { seenDot = true; return true }
            return false
        })
    }
}
