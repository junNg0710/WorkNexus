import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/paged_column_footer.dart
/// The foot of a paged column / table: skeleton cards while it auto-loads, "N of M checked · Load more" when a
/// filtered view stopped scanning by itself, or the error with Retry.
public struct PagedColumnFooter: View {
    @Environment(\.appTheme) private var theme
    let stream: PagedViewState; let visible: Int; let filtered: Bool; let errorText: String
    let onLoadMore: () -> Void; let onRetry: () -> Void

    public init(stream: PagedViewState, visible: Int, filtered: Bool, errorText: String,
                onLoadMore: @escaping () -> Void, onRetry: @escaping () -> Void) {
        self.stream = stream; self.visible = visible; self.filtered = filtered; self.errorText = errorText
        self.onLoadMore = onLoadMore; self.onRetry = onRetry
    }

    public var body: some View {
        if stream.failure != nil {
            FooterAction(note: AppInlineNote(errorText, isError: true), label: appString("retry", "Retry"), icon: "arrow.clockwise", action: onRetry)
        } else {
            let auto = ShouldAutoLoad()(AutoLoadQuery(state: stream, filtered: filtered, visible: visible))
            if !auto && !stream.loading {
                let scanned = min(stream.page * kPagedViewPageSize, stream.total)
                FooterAction(note: AppInlineNote(appFormat("pagedScanned", "%1$@ of %2$@ checked", "\(scanned)", "\(stream.total)")),
                             label: appString("pagedLoadMore", "Load more"), icon: "chevron.down.2", action: onLoadMore)
            } else {
                VStack(spacing: theme.spacing.s8) {
                    ForEach(0..<(visible == 0 ? 3 : 2), id: \.self) { _ in SkeletonBox(height: 78, radius: theme.radii.sm) }
                }
                .task(id: "\(stream.page)|\(stream.loading)|\(visible)|\(stream.dryLoads)") { if auto { onLoadMore() } }
            }
        }
    }
}

private struct FooterAction<Note: View>: View {
    @Environment(\.appTheme) private var theme
    let note: Note; let label: String; let icon: String; let action: () -> Void
    var body: some View {
        VStack(spacing: theme.spacing.s4) { note; AppButton(label, systemImage: icon, kind: .ghost, action: action) }
            .frame(maxWidth: .infinity).padding(.vertical, theme.spacing.s6)
    }
}

/// A column count badge with a trailing "+" while the view has more pages.
public struct PagedColumnCount: View {
    @Environment(\.appTheme) private var theme
    let count: Int; let more: Bool
    public init(_ count: Int, more: Bool = false) { self.count = count; self.more = more }
    public var body: some View {
        HStack(spacing: theme.spacing.s2) {
            AppCountBadge(count)
            if more { Text("+").font(theme.typography.mono.weight(.semibold)).foregroundStyle(theme.colors.tx3) }
        }
    }
}
