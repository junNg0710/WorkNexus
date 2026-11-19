import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/{board_toolbar,board_toolbar_layout,render_board_toolbar}.dart
/// The strip above a board: scope tabs, filters button (and, on the Kanban view, the card Sort button), search, refresh
/// and view-mode switch, plus an optional row
/// (`below`, e.g. the active-filter bar). It degrades with the width: full → icon-only view modes → scopes as a menu →
/// no search field (`ViewThatFits`).
public struct BoardToolbar<Filters: View, Refresh: View, Below: View>: View {
    @Environment(\.appTheme) private var theme
    let controller: BoardController
    let scopes: [AppSegmentedTab]; let searchScope: String?
    let modes: [ToolViewMode]; let viewMode: ViewModeID; let onViewMode: (ViewModeID) -> Void
    let filters: Filters; let refresh: Refresh; let below: Below
    /// What the Kanban view's Sort button offers; the List view sorts by its own column headers, so it gets none.
    let sortFields: [TicketSortField]

    public init(controller: BoardController, scopes: [AppSegmentedTab] = [], searchScope: String? = nil,
                modes: [ToolViewMode], viewMode: ViewModeID, onViewMode: @escaping (ViewModeID) -> Void,
                sortFields: [TicketSortField] = TicketSortField.boardFields,
                @ViewBuilder filters: () -> Filters, @ViewBuilder refresh: () -> Refresh, @ViewBuilder below: () -> Below) {
        self.controller = controller; self.scopes = scopes; self.searchScope = searchScope; self.modes = modes
        self.viewMode = viewMode; self.onViewMode = onViewMode; self.sortFields = sortFields
        self.filters = filters(); self.refresh = refresh(); self.below = below()
    }

    /// The Sort button's fields, on the Kanban view only (the view mode id every board section gives it is `board`).
    private var shownSortFields: [TicketSortField] { viewMode == "board" ? sortFields : [] }

    /// From the widest arrangement to the narrowest; `ViewThatFits` picks the first that fits.
    fileprivate static var layouts: [ToolbarLayout] {
        [ToolbarLayout(iconOnlyModes: false, scopesAsMenu: false, search: true), ToolbarLayout(iconOnlyModes: true, scopesAsMenu: false, search: true),
         ToolbarLayout(iconOnlyModes: true, scopesAsMenu: true, search: true), ToolbarLayout(iconOnlyModes: true, scopesAsMenu: true, search: false)]
    }

    private var modeTabs: [AppSegmentedTab] {
        modes.map { m in
            AppSegmentedTab(label: appString(m.label, m.label), active: m.id == viewMode, icon: m.systemImage,
                            help: m.id == "list" ? appString("tipViewList", "Show as a table with sortable columns")
                                  : (m.id == "board" ? appString("tipViewBoard", "Show as a kanban board: a column per status") : nil)) { onViewMode(m.id) }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                ToolbarRow(controller: controller, scopes: scopes, searchScope: searchScope, modeTabs: modes.count > 1 ? modeTabs : [], layout: Self.layouts[0], sortFields: shownSortFields, filters: filters, refresh: refresh)
                ToolbarRow(controller: controller, scopes: scopes, searchScope: searchScope, modeTabs: modes.count > 1 ? modeTabs : [], layout: Self.layouts[1], sortFields: shownSortFields, filters: filters, refresh: refresh)
                ToolbarRow(controller: controller, scopes: scopes, searchScope: searchScope, modeTabs: modes.count > 1 ? modeTabs : [], layout: Self.layouts[2], sortFields: shownSortFields, filters: filters, refresh: refresh)
                ToolbarRow(controller: controller, scopes: scopes, searchScope: searchScope, modeTabs: modes.count > 1 ? modeTabs : [], layout: Self.layouts[3], sortFields: shownSortFields, filters: filters, refresh: refresh)
            }
            // The search results hang below the field, over `below` (the leader bar, the active filters): drawn after,
            // `below` would take the clicks meant for them.
            .zIndex(1)
            below
        }
        .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
        .zIndex(5)
    }
}

fileprivate struct ToolbarLayout { var iconOnlyModes: Bool; var scopesAsMenu: Bool; var search: Bool }

private struct ToolbarRow<Filters: View, Refresh: View>: View {
    @Environment(\.appTheme) private var theme
    let controller: BoardController; let scopes: [AppSegmentedTab]; let searchScope: String?; let modeTabs: [AppSegmentedTab]
    let layout: ToolbarLayout; let sortFields: [TicketSortField]; let filters: Filters; let refresh: Refresh
    var body: some View {
        HStack(spacing: theme.spacing.s6) {
            if !scopes.isEmpty { if layout.scopesAsMenu { ScopesMenu(tabs: scopes) } else { AppSegmentedTabs(scopes).fixedSize() } }
            filters
            if !sortFields.isEmpty { BoardSortButton(nav: controller.nav, fields: sortFields) }
            if layout.search { ContextualSearchField(controller: controller, scope: searchScope).frame(minWidth: 160, maxWidth: 480) }
            else { Spacer(minLength: 0) }
            refresh
            if !modeTabs.isEmpty { AppSegmentedTabs(modeTabs, iconOnly: layout.iconOnlyModes).fixedSize().layoutPriority(2) }
        }
    }
}

public extension BoardToolbar where Filters == FiltersButton, Below == ActiveFilterBar {
    /// Toolbar with the standard `FiltersButton` and `ActiveFilterBar`.
    init(controller: BoardController, scopes: [AppSegmentedTab] = [], searchScope: String? = nil, modes: [ToolViewMode],
         viewMode: ViewModeID, onViewMode: @escaping (ViewModeID) -> Void, catalog: BoardFacetCatalog? = nil,
         statusOption: FacetStatusOption? = nil, sortFields: [TicketSortField] = TicketSortField.boardFields,
         @ViewBuilder refresh: () -> Refresh) {
        self.init(controller: controller, scopes: scopes, searchScope: searchScope, modes: modes, viewMode: viewMode,
                  onViewMode: onViewMode, sortFields: sortFields,
                  filters: { FiltersButton(controller: controller, statusOption: statusOption, catalog: catalog) },
                  refresh: refresh,
                  below: { ActiveFilterBar(controller: controller, catalog: catalog, statusOption: statusOption) })
    }
}

/// The scope tabs collapsed into a menu button (Flutter `AppSegmentedTabsMenu`).
private struct ScopesMenu: View {
    @Environment(\.appTheme) private var theme
    let tabs: [AppSegmentedTab]
    var body: some View {
        AppMenuButton(items: { tabs.map { t in AppNativeMenu.Item(t.label) { t.onTap() } } }) {
            HStack(spacing: theme.spacing.s4) {
                Text(tabs.first(where: \.active)?.label ?? "").font(theme.typography.metaStrong)
                Image(systemName: "chevron.down").font(.system(size: theme.sizes.icon12))
            }
            .padding(.horizontal, theme.spacing.s10).frame(height: theme.sizes.control32)
            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
        }
        .fixedSize()
    }
}
