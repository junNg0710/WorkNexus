import CoreUI
import SwiftUI

/// Ported from: lib/features/connections/presentation/widgets/workspace_editor_parts.dart
/// One colour swatch of the workspace colour picker; the outline (not a tint) answers hover and selection.
struct WorkspaceColorChoice: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let value: Int
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        let color = Color(argb: UInt32(truncatingIfNeeded: value))
        RoundedRectangle(cornerRadius: theme.radii.sm).fill(color)
            .frame(width: theme.sizes.control32 + theme.spacing.s8, height: theme.sizes.control32)
            .overlay(RoundedRectangle(cornerRadius: theme.radii.sm)
                .stroke(selected || hovering ? theme.colors.tx : theme.colors.line,
                        lineWidth: selected ? theme.borders.thick : theme.borders.hairline))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }.onTapGesture(perform: onTap).pointerStyle(.link)
            .accessibilityLabel(String(format: "#%06X", value & 0xFFFFFF))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The custom-icon row: the badge as it will look, the picked file's name, "Choose file" and a clear button.
struct WorkspaceIconFilePicker: View {
    @Environment(\.appTheme) private var theme
    let colorValue: Int
    let shortCode: String
    let iconKey: String
    let fileName: String?
    let onPick: () -> Void
    let onClear: (() -> Void)?

    var body: some View {
        let c = theme.colors
        let hasImage = WorkspaceIcons.imageData(iconKey) != nil
        HStack(spacing: theme.spacing.s10) {
            WorkspaceBadge(Color(argb: UInt32(truncatingIfNeeded: colorValue)), shortCode, big: true, iconKey: iconKey)
            Text(hasImage ? (fileName ?? L.customIconSelected) : L.noFileSelected)
                .font(theme.typography.meta).foregroundStyle(hasImage ? c.tx : c.tx3).lineLimit(1)
            Spacer(minLength: 0)
            AppButton(L.chooseFile, action: onPick)
            if let onClear { AppIconButton("xmark", help: L.removeCustomIcon, action: onClear) }
        }
        .padding(theme.spacing.s10)
        .background(c.panel, in: RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(c.line, lineWidth: theme.borders.hairline))
    }
}
