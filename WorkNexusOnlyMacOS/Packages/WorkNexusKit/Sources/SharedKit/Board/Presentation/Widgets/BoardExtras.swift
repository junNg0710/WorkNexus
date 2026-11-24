import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/{board_refresh_button,board_layout_toggle,empty_state}.dart

/// Refresh button (⌘R) with a spinner while `loading`.
public struct BoardRefreshButton: View {
    @Environment(\.appTheme) private var theme
    @KeptAwake private var sectionActive
    let loading: Bool; let onPressed: () -> Void
    public init(loading: Bool, onPressed: @escaping () -> Void) { self.loading = loading; self.onPressed = onPressed }
    public var body: some View {
        Button { if !loading { onPressed() } } label: {
            Group {
                if loading { ProgressView().controlSize(.small) }
                else { Image(systemName: "arrow.clockwise").font(.system(size: theme.sizes.icon16)) }
            }
            .foregroundStyle(theme.colors.tx2).frame(width: theme.sizes.control32, height: theme.sizes.control32)
            .background(theme.colors.panel, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay { if theme.showOutline { RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline) } }
        }
        .buttonStyle(.plain).keptShortcut("r", modifiers: .command).help(appString("refresh", "Refresh"))
        // The menu's ⌘R refreshes the board on screen first (a hidden, kept-alive board must not answer it).
        .focusedSceneValue(\.boardRefresh, sectionActive && !loading ? onPressed : nil)
    }
}

/// Board / Table switch, stored in `AppSettings.boardLayout`.
public struct BoardLayoutToggle: View {
    let controller: BoardController
    public init(controller: BoardController) { self.controller = controller }
    public var body: some View {
        let layout = controller.settings.boardLayout
        AppSegmentedTabs([
            AppSegmentedTab(label: appString("boardLayoutBoard", "Board"), active: layout == .board, icon: "rectangle.split.3x1") { controller.setBoardLayout(.board) },
            AppSegmentedTab(label: appString("boardLayoutTable", "Table"), active: layout == .table, icon: "tablecells") { controller.setBoardLayout(.table) },
        ])
    }
}

/// Nothing to show: either no tickets yet, or the filters hide them all (with a "clear filters" action).
public struct BoardEmptyState: View {
    @Environment(\.appTheme) private var theme
    let controller: BoardController
    public init(controller: BoardController) { self.controller = controller }
    public var body: some View {
        let c = theme.colors
        let filtered = controller.filter.hasActiveFilters
        VStack(spacing: theme.spacing.s8) {
            Image(systemName: filtered ? "magnifyingglass" : "rectangle.split.3x1").font(.system(size: theme.sizes.icon24 * 1.5)).foregroundStyle(c.tx3)
            Text(filtered ? appString("emptyTitle", "No tasks match these filters") : appString("boardEmptyTitle", "Nothing here yet"))
                .font(theme.typography.titleSm).foregroundStyle(c.tx)
            Text(filtered ? appString("emptyDesc", "Try clearing a filter or switching workspace.") : appString("boardEmptyDesc", "Tasks show up here as soon as they sync."))
                .font(theme.typography.body).foregroundStyle(c.tx2).multilineTextAlignment(.center)
            if filtered { AppButton(appString("clearAllFilters", "Clear all filters"), kind: .primary) { controller.clearAll() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(theme.spacing.s24)
    }
}
