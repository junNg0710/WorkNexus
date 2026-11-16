import CoreUI
import SwiftUI

/// Ported from: lib/core/widgets/editor_chip.dart
/// A small removable chip (a picked option, a file to attach).
struct EditorChip: View {
    @Environment(\.appTheme) private var theme
    let label: String
    var systemImage: String?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx3) }
            Text(label).font(theme.typography.meta).foregroundStyle(theme.colors.tx).lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: theme.sizes.icon12 - 3, weight: .bold)).foregroundStyle(theme.colors.tx3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s4)
        .background(theme.colors.card, in: RoundedRectangle(cornerRadius: theme.radii.sm))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.sm).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}
