import CoreUI
import SwiftUI

/// Ported from: lib/features/panic_switch/presentation/widgets/panic_check_row.dart
/// A tickable row of the "Thầy vô" lists (apps to open, allowed senders): the whole row toggles, and shows a rounded,
/// outlined tint on hover. `leading` is an avatar or an app icon. When not `enabled` it only shows `picked`.
struct PanicCheckRow<Leading: View>: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let label: String
    var detail: String?
    var picked: Bool
    var enabled = true
    let onToggle: () -> Void
    @ViewBuilder var leading: Leading

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radii.md)
        let lit = hovering && enabled
        Button(action: onToggle) {
            HStack(spacing: theme.spacing.s10) {
                AppCheckMark(checked: picked, enabled: enabled)
                leading
                Text(label).font(theme.typography.body).foregroundStyle(enabled ? theme.colors.tx : theme.colors.tx2).lineLimit(1)
                Spacer(minLength: theme.spacing.s8)
                if let detail { Text(detail).font(theme.typography.caption).foregroundStyle(theme.colors.tx3).lineLimit(1) }
            }
            .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s8)
            .background(lit ? theme.colors.sel : .clear, in: shape)
            .overlay(shape.stroke(lit ? theme.colors.line : .clear, lineWidth: theme.borders.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).onHover { hovering = $0 }
    }
}

extension PanicCheckRow where Leading == EmptyView {
    init(label: String, detail: String? = nil, picked: Bool, enabled: Bool = true, onToggle: @escaping () -> Void) {
        self.init(label: label, detail: detail, picked: picked, enabled: enabled, onToggle: onToggle) { EmptyView() }
    }
}
