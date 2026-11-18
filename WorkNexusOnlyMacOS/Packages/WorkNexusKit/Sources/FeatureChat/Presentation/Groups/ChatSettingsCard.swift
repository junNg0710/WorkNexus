import CoreUI
import SwiftUI

/// A few settings on a card: rows split by hairlines, each row's hover clipped to the card's rounded corners.
/// Ported from: lib/core/widgets/quick_settings_parts.dart (`QuickSettingsCard`)
struct ChatSettingsCard<Content: View>: View {
    @Environment(\.appTheme) private var theme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows.indices, id: \.self) { i in
                    if i > 0 { Divider().overlay(theme.colors.line) }
                    rows[i]
                }
            }
        }
        .background(theme.colors.panel)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).stroke(theme.colors.line, lineWidth: theme.borders.hairline) }
    }
}

/// A labelled switch with a hint under the label; the whole row toggles it. Disabled (`enabled: false`) it shows its
/// value but cannot be changed.
/// Ported from: lib/core/widgets/quick_settings_parts.dart (`QuickSettingsSwitchField`)
struct ChatSwitchRow: View {
    @Environment(\.appTheme) private var theme
    let label: String
    let hint: String
    @Binding var isOn: Bool
    var enabled = true

    var body: some View {
        HoverSurface(onTap: { isOn.toggle() }, enabled: enabled, cornerRadius: 0) {
            HStack(spacing: theme.spacing.s12) {
                VStack(alignment: .leading, spacing: theme.spacing.s2) {
                    Text(label).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                    Text(hint).font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(!enabled)
            }
            .padding(.horizontal, theme.spacing.s16).padding(.vertical, theme.spacing.s12)
        }
    }
}
