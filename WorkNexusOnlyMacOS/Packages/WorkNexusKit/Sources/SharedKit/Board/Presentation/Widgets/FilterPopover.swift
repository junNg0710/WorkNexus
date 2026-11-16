import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/{filters_button,filter_popover,filter_popover_anchor}.dart
/// The "Filters" button: a funnel + active count that opens the filter popover (saved presets + facet or generic groups).
public struct FiltersButton: View {
    @Environment(\.appTheme) private var theme
    let controller: BoardController
    var compact = false; var statusOption: FacetStatusOption?; var catalog: BoardFacetCatalog?; var onPick: (() -> Void)?
    @State private var open = false

    public init(controller: BoardController, compact: Bool = false, statusOption: FacetStatusOption? = nil,
                catalog: BoardFacetCatalog? = nil, onPick: (() -> Void)? = nil) {
        self.controller = controller; self.compact = compact; self.statusOption = statusOption; self.catalog = catalog; self.onPick = onPick
    }

    public var body: some View {
        if controller.filterHasGroups {
            let c = theme.colors
            let count = controller.filter.activeTokenCount
            let active = count > 0
            let ink = active ? c.accent : c.tx2
            HoverSurface(onTap: { open.toggle() }, height: theme.sizes.control32, fill: active ? c.sel : c.panel,
                         border: theme.showOutline ? c.line : nil) {
                HStack(spacing: theme.spacing.s6) {
                    Image(systemName: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                        .font(.system(size: theme.sizes.icon16)).foregroundStyle(ink)
                    if !compact { Text(appString("filters", "Filters")).font(theme.typography.metaStrong).foregroundStyle(ink) }
                    if active { AppCountBadge(count) }
                }
                .padding(.horizontal, compact ? theme.spacing.s8 : theme.spacing.s12)
            }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                FilterPopover(controller: controller, statusOption: statusOption, catalog: catalog, onPick: onPick)
            }
        }
    }
}

public struct FilterPopover: View {
    @Environment(\.appTheme) private var theme
    let controller: BoardController
    var statusOption: FacetStatusOption?; var catalog: BoardFacetCatalog?; var onPick: (() -> Void)?

    public init(controller: BoardController, statusOption: FacetStatusOption? = nil, catalog: BoardFacetCatalog? = nil,
                onPick: (() -> Void)? = nil) {
        self.controller = controller; self.statusOption = statusOption; self.catalog = catalog; self.onPick = onPick
    }

    public var body: some View {
        let count = controller.filter.activeTokenCount
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.s12) {
                HStack(spacing: theme.spacing.s6) {
                    Text(appString("filters", "Filters")).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                    if count > 0 { AppCountBadge(count) }
                    Spacer()
                    AppButton(appString("filtersClearAll", "Clear all"), systemImage: "arrow.counterclockwise", kind: .ghost) { controller.clearAll() }
                        .disabled(!controller.filter.hasActiveFilters)
                }
                SavedFiltersSection(controller: controller)
                if controller.facetScope != .none || controller.usesFacetFilters {
                    FacetFilterGroups(controller: controller, statusOption: statusOption, catalog: catalog, onPick: onPick)
                } else {
                    GenericFilterGroups(controller: controller)
                }
            }
            .padding(EdgeInsets(top: theme.spacing.s14, leading: theme.spacing.s20, bottom: theme.spacing.s20, trailing: theme.spacing.s20))
        }
        .frame(width: 440).frame(minHeight: 320, maxHeight: 720)
        .background(theme.colors.panel)
    }
}
