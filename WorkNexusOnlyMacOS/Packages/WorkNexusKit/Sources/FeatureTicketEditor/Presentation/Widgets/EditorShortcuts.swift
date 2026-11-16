import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/editor_shortcuts.dart
/// The editor's keys: Esc does what Cancel does, Cmd-S what Save does (nothing while `onSave` is nil). Hidden
/// buttons carry the shortcuts, so they work whichever field has focus.
private struct EditorShortcuts: ViewModifier {
    let onClose: () -> Void
    let onSave: (() -> Void)?

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                Button("", action: onClose).keyboardShortcut(.cancelAction)
                Button("") { onSave?() }.keyboardShortcut("s", modifiers: .command)
            }
            .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

extension View {
    func editorShortcuts(onClose: @escaping () -> Void, onSave: (() -> Void)?) -> some View {
        modifier(EditorShortcuts(onClose: onClose, onSave: onSave))
    }
}
