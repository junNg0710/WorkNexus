import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/{board_toolbar,board_toolbar_layout,render_board_toolbar}.dart
/// The strip above a board: scope tabs, filters button (and, on the Kanban view, the card Sort button), search, refresh
/// and view-mode switch, plus an optional row
/// (`below`, e.g. the active-filter bar). It degrades with the width: full → icon-only view modes → scopes as a menu →
/// no search field. One row is drawn, its arrangement worked out from its pieces' widths (`BoardToolbarFit`).
public struct BoardToolbar<Filters: View, Refresh: View, Below: View>: View {
    @Environment(\.appTheme) private var theme
    let controller: BoardController
    let scopes: [AppSegmentedTab]; let searchScope: String?
    let modes: [ToolViewMode]; let viewMode: ViewModeID; let onViewMode: (ViewModeID) -> Void
    let filters: Filters; let refresh: Refresh; let below: Below
    /// What the Kanban view's Sort button offers; the List view sorts by its own column headers, so it gets none.
    let sortFields: [TicketSortField]
    @State private var fit = BoardToolbarFit()
    @State private var available: CGFloat = .greatestFiniteMagnitude

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

    private var shownModeTabs: [AppSegmentedTab] { modes.count > 1 ? modeTabs : [] }

    private var modeTabs: [AppSegmentedTab] {
        modes.map { m in
            AppSegmentedTab(label: appString(m.label, m.label), active: m.id == viewMode, icon: m.systemImage,
                            help: m.id == "list" ? appString("tipViewList", "Show as a table with sortable columns")
                                  : (m.id == "board" ? appString("tipViewBoard", "Show as a kanban board: a column per status") : nil)) { onViewMode(m.id) }
        }
    }

    /// The arrangement for the width there is (one row is drawn; see `BoardToolbarFit`).
    private var layout: BoardToolbarFit.Layout {
        let pieces = (scopes.isEmpty ? 0 : 1) + 1 + (shownSortFields.isEmpty ? 0 : 1) + 2 + (shownModeTabs.isEmpty ? 0 : 1)
        return fit.layout(available: available, searchMin: BoardToolbarFit.searchMin, spacing: theme.spacing.s6, pieces: pieces)
    }

    public var body: some View {
        let modeTabs = shownModeTabs
        VStack(alignment: .leading, spacing: 0) {
            ToolbarRow(controller: controller, scopes: scopes, searchScope: searchScope, modeTabs: modeTabs, layout: layout,
                       sortFields: shownSortFields, filters: filters, refresh: refresh, others: $fit.others)
                // The pieces that change between arrangements, measured once each, out of sight.
                .background(alignment: .topLeading) { ToolbarProbes(scopes: scopes, modeTabs: modeTabs, fit: $fit).hidden() }
                // The width there is: this frame takes what it is offered (`minWidth: 0`) whatever the row wants, so a row
                // too wide for it cannot widen the measure and keep itself from folding.
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
                // The search results hang below the field, over `below` (the leader bar, the active filters): drawn
                // after, `below` would take the clicks meant for them.
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

private struct ToolbarRow<Filters: View, Refresh: View>: View {
    @Environment(\.appTheme) private var theme
    let controller: BoardController; let scopes: [AppSegmentedTab]; let searchScope: String?; let modeTabs: [AppSegmentedTab]
    let layout: BoardToolbarFit.Layout; let sortFields: [TicketSortField]; let filters: Filters; let refresh: Refresh
    /// Filters + Sort + Refresh, as drawn: the same in every arrangement.
    @Binding var others: CGFloat
    @State private var widths: [Int: CGFloat] = [:]

    var body: some View {
        HStack(spacing: theme.spacing.s6) {
            if !scopes.isEmpty { if layout.scopesAsMenu { ScopesMenu(tabs: scopes) } else { AppSegmentedTabs(scopes).fixedSize() } }
            filters.measuredWidth { note(0, $0) }
            if !sortFields.isEmpty { BoardSortButton(nav: controller.nav, fields: sortFields).measuredWidth { note(1, $0) } }
            if layout.search { ContextualSearchField(controller: controller, scope: searchScope).frame(minWidth: BoardToolbarFit.searchMin, maxWidth: 480) }
            else { Spacer(minLength: 0) }
            refresh.measuredWidth { note(2, $0) }
            if !modeTabs.isEmpty { AppSegmentedTabs(modeTabs, iconOnly: layout.iconOnlyModes).fixedSize().layoutPriority(2) }
        }
        .onChange(of: sortFields.isEmpty) { _, none in if none { note(1, 0) } }
    }

    private func note(_ piece: Int, _ width: CGFloat) {
        widths[piece] = width
        let sum = widths.values.reduce(0, +)
        if abs(sum - others) >= 1 { others = sum }
    }
}

/// The scope tabs and view modes in each of their forms, laid out only to be measured (hidden by the caller).
private struct ToolbarProbes: View {
    let scopes: [AppSegmentedTab]; let modeTabs: [AppSegmentedTab]
    @Binding var fit: BoardToolbarFit

    var body: some View {
        VStack(alignment: .leading) {
            if !scopes.isEmpty {
                AppSegmentedTabs(scopes).fixedSize().measuredWidth { set(\.scopesTabs, $0) }
                ScopesMenuLabel(tabs: scopes).fixedSize().measuredWidth { set(\.scopesMenu, $0) }
            }
            if !modeTabs.isEmpty {
                AppSegmentedTabs(modeTabs).fixedSize().measuredWidth { set(\.modesWithLabels, $0) }
                AppSegmentedTabs(modeTabs, iconOnly: true).fixedSize().measuredWidth { set(\.modesIconOnly, $0) }
            }
        }
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func set(_ key: WritableKeyPath<BoardToolbarFit, CGFloat>, _ w: CGFloat) { if abs(fit[keyPath: key] - w) >= 1 { fit[keyPath: key] = w } }
}

private extension View {
    /// Calls `report` with the width this view is drawn at, now and whenever it changes.
    func measuredWidth(_ report: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.width } action: { report($0) }
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
        AppMenuButton(items: { tabs.map { t in AppNativeMenu.Item(t.label) { t.onTap() } } }) { ScopesMenuLabel(tabs: tabs) }
            .fixedSize()
    }
}

/// What the scopes menu button shows: the open scope and a chevron.
private struct ScopesMenuLabel: View {
    @Environment(\.appTheme) private var theme
    let tabs: [AppSegmentedTab]
    var body: some View {
        HStack(spacing: theme.spacing.s4) {
            Text(tabs.first(where: \.active)?.label ?? "").font(theme.typography.metaStrong)
            Image(systemName: "chevron.down").font(.system(size: theme.sizes.icon12))
        }
        .padding(.horizontal, theme.spacing.s10).frame(height: theme.sizes.control32)
        .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
    }
}
