/// Ported from: lib/features/workspace_overview/presentation/widgets/tool_card_metrics.dart
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Renders the 2 metrics on a workspace tool overview card: count and label from the tool's `metrics` stream (the
/// local database), or a skeleton while loading.
struct ToolCardMetrics: View {
    @Environment(\.appTheme) private var theme
    let module: any ToolModule
    let account: Account
    @State private var metrics: ToolMetrics?

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.s10) {
            if let metrics {
                MetricTile(count: metrics.primaryCount, label: metrics.primaryLabel)
                if let n = metrics.secondaryCount, let label = metrics.secondaryLabel { MetricTile(count: n, label: label) }
                else { Spacer(minLength: 0).frame(maxWidth: .infinity) }
            } else {
                MetricSkeleton(); MetricSkeleton()
            }
        }
        .task(id: account.id) {
            for await m in module.metrics(account: account) { metrics = m }
        }
    }
}

private struct MetricTile: View {
    @Environment(\.appTheme) private var theme
    let count: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s2) {
            Text(verbatim: "\(count)").font(theme.typography.title.weight(.bold)).foregroundStyle(theme.colors.tx)
            Text(label).font(theme.typography.caption).foregroundStyle(theme.colors.tx2).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetricSkeleton: View {
    @Environment(\.appTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            SkeletonBox(width: theme.sizes.control32 + theme.spacing.s16, height: theme.sizes.icon24)
            SkeletonBox(width: theme.sizes.control32 * 2 + theme.spacing.s8, height: theme.sizes.icon12, radius: theme.radii.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
