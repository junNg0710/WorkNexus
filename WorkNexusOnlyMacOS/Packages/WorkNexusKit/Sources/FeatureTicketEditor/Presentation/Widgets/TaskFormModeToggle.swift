import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/task_form_mode_toggle.dart
/// A pill toggle between the simple form (only what a task needs) and the full one.
struct TaskFormModeToggle: View {
    @Environment(\.appTheme) private var theme
    let isSimple: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Segment(label: appString("taskFormModeSimple", "Simple"), selected: isSimple) { onToggle(true) }
            Segment(label: appString("taskFormModeFull", "Full"), selected: !isSimple) { onToggle(false) }
        }
        .padding(theme.spacing.s2)
        .background(theme.colors.panel2, in: Capsule())
        .overlay(Capsule().stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}

private struct Segment: View {
    @Environment(\.appTheme) private var theme
    let label: String
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label).font(theme.typography.label).foregroundStyle(selected ? theme.colors.accentTx : theme.colors.tx2)
                .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s4)
                .background(selected ? theme.colors.accent : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
