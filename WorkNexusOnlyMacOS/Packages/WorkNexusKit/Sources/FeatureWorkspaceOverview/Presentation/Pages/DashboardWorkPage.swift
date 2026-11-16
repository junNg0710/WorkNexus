/// Ported from: lib/features/workspace_overview/presentation/pages/dashboard_work_page.dart
import CoreDomain
import CoreUI
import SwiftUI

/// Every task and bug assigned to the user on one ZenTao account, shown in the Overview's place from a ZenTao
/// section's "Show all"; the header's back button returns to the Overview.
struct DashboardWorkPage: View {
    @Environment(\.appTheme) private var theme
    @State private var width: CGFloat = 0
    let model: OverviewModel
    let account: Account
    let kind: DashboardItemKind

    var body: some View {
        let s = theme.spacing
        let both = width >= OverviewLayout.workTwoColumnsWidth
        VStack(spacing: 0) {
            // The header on a panel bar set off by a hairline, like chat's.
            DashboardWorkHeader(model: model, account: account, kind: kind, both: both)
                .frame(maxWidth: OverviewLayout.workPageMaxWidth, alignment: .leading).frame(maxWidth: .infinity)
                .padding(EdgeInsets(top: s.s16, leading: s.s24, bottom: s.s16, trailing: s.s24))
                .background(theme.colors.panel)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
            DashboardWorkView(model: model, account: account, kind: kind, both: both)
                .frame(maxWidth: OverviewLayout.workPageMaxWidth).frame(maxWidth: .infinity)
                .padding(EdgeInsets(top: s.s20, leading: s.s24, bottom: s.s24, trailing: s.s24))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.bg)
        .onGeometryChange(for: CGFloat.self) { $0.size.width - 2 * theme.spacing.s24 } action: { width = $0 }
    }
}
