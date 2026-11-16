/// Ported from: lib/features/workspace_overview/presentation/widgets/dashboard_row.dart
import CoreUI
import SwiftUI

/// One line of a dashboard list: `leading`, a title over an optional `subtitle`, and `trailing` chips.
/// Hover-highlighted and clickable when `onTap` is set.
struct DashboardRow<Leading: View, Trailing: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    var subtitle: String?
    var onTap: (() -> Void)?
    let leading: Leading
    let trailing: Trailing

    init(title: String, subtitle: String? = nil, onTap: (() -> Void)? = nil, @ViewBuilder leading: () -> Leading,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.subtitle = subtitle; self.onTap = onTap; self.leading = leading(); self.trailing = trailing()
    }

    var body: some View {
        HoverSurface(onTap: onTap) {
            HStack(spacing: theme.spacing.s8) {
                leading
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(theme.typography.caption).foregroundStyle(theme.colors.tx3).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: theme.spacing.s6) { trailing }
            }
            .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s6)
        }
    }
}
