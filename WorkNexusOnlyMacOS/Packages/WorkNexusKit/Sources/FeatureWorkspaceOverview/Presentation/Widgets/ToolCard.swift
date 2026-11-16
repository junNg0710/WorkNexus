/// Ported from: lib/features/workspace_overview/presentation/widgets/tool_card.dart
import CoreDomain
import CoreUI
import SwiftUI

/// A tool account card for the Workspace Overview grid (design §5, specs S6.1): account info, role, 2 metrics,
/// section chips and an "Open {Tool} →" action.
struct ToolCard: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let account: Account

    var body: some View {
        if let module = model.registry.module(for: account.providerType) {
            CardSurface(padding: theme.spacing.s12) {
                VStack(alignment: .leading, spacing: theme.spacing.s10) {
                    ToolCardIdentity(account: account, module: module)
                    Divider().overlay(theme.colors.line)
                    ToolCardMetrics(module: module, account: account)
                    ToolSectionChips(model: model, account: account, module: module)
                    ToolOpenButton(model: model, account: account)
                }
            }
            .frame(minWidth: OverviewLayout.toolCardMinWidth)
        }
    }
}

/// The tool cards fill one row (up to three columns by width); fewer tools than columns share the row instead of
/// leaving columns empty.
struct ToolCardGrid: View {
    let model: OverviewModel
    let accounts: [Account]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ToolCardColumns(model: model, accounts: accounts, fits: 3)
            ToolCardColumns(model: model, accounts: accounts, fits: 2)
            ToolCardColumns(model: model, accounts: accounts, fits: 1)
        }
    }
}

private struct ToolCardColumns: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let accounts: [Account]
    let fits: Int

    var body: some View {
        let n = max(1, min(accounts.count, fits))
        let rows = stride(from: 0, to: accounts.count, by: n).map { Array(accounts[$0..<min($0 + n, accounts.count)]) }
        VStack(spacing: theme.spacing.s10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: theme.spacing.s10) {
                    ForEach(row) { ToolCard(model: model, account: $0).frame(maxWidth: .infinity) }
                    ForEach(0..<(n - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 0) }
                }
            }
        }
        .frame(minWidth: CGFloat(n) * OverviewLayout.toolCardMinWidth + CGFloat(n - 1) * theme.spacing.s10)
    }
}
