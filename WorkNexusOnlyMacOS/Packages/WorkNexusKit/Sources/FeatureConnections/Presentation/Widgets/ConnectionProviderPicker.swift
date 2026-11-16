import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/connections/presentation/widgets/connection_provider_picker.dart
/// The providers an account can be connected from, one tile each; `value` is the one whose form shows. Jira is
/// not supported yet: its tile is dimmed and says so on hover.
struct ConnectionProviderPicker: View {
    @Environment(\.appTheme) private var theme
    let value: ProviderType
    let onChanged: (ProviderType) -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s10) {
            ForEach(ProviderType.allCases, id: \.self) { p in
                ProviderTile(provider: p, selected: p == value, onTap: p == .jira ? nil : { onChanged(p) })
            }
        }
    }
}

private struct ProviderTile: View {
    @Environment(\.appTheme) private var theme
    let provider: ProviderType
    let selected: Bool
    let onTap: (() -> Void)?

    var body: some View {
        let c = theme.colors
        HoverSurface(onTap: onTap, selected: selected, enabled: onTap != nil, fill: selected ? c.sel : c.panel2,
                     border: selected ? c.accent : c.line) {
            HStack(spacing: theme.spacing.s6) {
                BrandLogoBadge(provider, size: theme.sizes.icon20)
                Text(provider.displayName).font(theme.typography.label).lineLimit(1)
                    .foregroundStyle(selected ? c.tx : c.tx2)
            }
            .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s10)
            .frame(maxWidth: .infinity)
        }
        .help(onTap == nil ? L.comingSoon(provider.displayName) : "")
        .accessibilityLabel(provider.displayName)
    }
}
