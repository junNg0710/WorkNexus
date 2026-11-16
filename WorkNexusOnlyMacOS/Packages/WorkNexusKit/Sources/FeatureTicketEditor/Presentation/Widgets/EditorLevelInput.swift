import CoreDomain
import CoreUI
import SwiftUI

/// What a 1-4 level means, which decides its colors and labels.
enum EditorLevel { case severity, priority }

/// Ported from: lib/features/ticket_editor/presentation/widgets/editor_level_input.dart
/// A pick of 1-4 (severity or priority) as a row of chips tinted like the board's severity and priority tags; the
/// picked one is filled.
struct EditorLevelInput: View {
    @Environment(\.appTheme) private var theme
    let level: EditorLevel
    let value: Int
    let onChanged: (Int) -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s6) {
            ForEach(1...4, id: \.self) { i in
                LevelChip(label: label(i), color: color(i), selected: value == i) { onChanged(i) }
            }
        }
    }

    private func label(_ i: Int) -> String {
        switch level { case .severity: zentaoSeverityLabel(i) ?? "S\(i)"; case .priority: "Pri \(i)" }
    }

    private func color(_ i: Int) -> Color {
        switch level {
        case .severity: theme.colors.severityColor(i) ?? theme.colors.tx3
        case .priority: theme.colors.priorityColor(Priority.fromLevel(i - 1))
        }
    }
}

private struct LevelChip: View {
    @Environment(\.appTheme) private var theme
    let label: String
    let color: Color
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        let radius = RoundedRectangle(cornerRadius: theme.radii.md)
        Button(action: onTap) {
            HStack(spacing: theme.spacing.s4) {
                Circle().fill(selected ? color : color.opacity(0.5)).frame(width: theme.spacing.s6, height: theme.spacing.s6)
                Text(label).font(theme.typography.badge).foregroundStyle(selected ? color : theme.colors.tx2).lineLimit(1)
            }
            .padding(.vertical, theme.spacing.s6).padding(.horizontal, theme.spacing.s4)
            .frame(maxWidth: .infinity)
            .background(selected ? color.opacity(0.16) : theme.colors.panel2, in: radius)
            .overlay(radius.stroke(selected ? color.opacity(0.6) : theme.colors.line, lineWidth: theme.borders.hairline))
            .contentShape(radius)
        }
        .buttonStyle(.plain)
    }
}
