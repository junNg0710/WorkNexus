import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/active_filter_bar.dart
/// Chips of the active filters under the toolbar, each removable; an applied saved preset shows as one highlighted chip.
public struct ActiveFilterBar: View {
    @Environment(\.appTheme) private var theme
    let controller: BoardController
    var catalog: BoardFacetCatalog?; var statusOption: FacetStatusOption?

    public init(controller: BoardController, catalog: BoardFacetCatalog? = nil, statusOption: FacetStatusOption? = nil) {
        self.controller = controller; self.catalog = catalog; self.statusOption = statusOption
    }

    private func name(_ g: BoardFacetGroup, _ o: BoardFacetOption) -> String {
        if g.kind == .status, let statusOption { return statusOption(o, true, {}).label }
        return o.label ?? facetLabel(g.kind, o.value)
    }

    /// Whether this group's picks are exactly what the applied preset set (then the preset chip stands for them).
    private func fromPreset(_ g: BoardFacetGroup, _ picked: [BoardFacetOption], _ preset: FilterState?) -> Bool {
        guard let preset else { return false }
        let saved = Set(g.options.filter { facetActive(preset, g.kind, $0.value) }.map(\.value))
        return saved.count == picked.count && picked.allSatisfy { saved.contains($0.value) }
    }

    public var body: some View {
        let f = controller.filter
        if f.activeTokenCount > 0 {
            let applied = controller.savedFilters.first { IsSavedFilterApplied()($0, f) }
            FlowLayout(spacing: theme.spacing.s6) {
                if let applied { ActiveChip(label: nil, value: applied.name, highlighted: true) { controller.clearAll() } }
                ForEach(controller.facets(catalog: catalog).groups, id: \.kind) { g in
                    let picked = g.options.filter { facetActive(f, g.kind, $0.value) }
                    if !picked.isEmpty && !fromPreset(g, picked, applied?.filter) {
                        ActiveChip(label: facetHeader(g.kind), value: picked.map { name(g, $0) }.joined(separator: ", ")) { controller.clearFacet(g.kind) }
                    }
                }
                AppButton(appString("clearAllFilters", "Clear all filters"), kind: .ghost) { controller.clearAll() }
            }
            .padding(.top, theme.spacing.s6)
        }
    }
}

private struct ActiveChip: View {
    @Environment(\.appTheme) private var theme
    let label: String?; let value: String; var highlighted = false; let onRemove: () -> Void
    var body: some View {
        let c = theme.colors
        HStack(spacing: theme.spacing.s4) {
            if let label { Text(label).font(theme.typography.meta).foregroundStyle(c.tx2) }
            Text(value).font(theme.typography.metaStrong).foregroundStyle(highlighted ? c.accent : c.tx).lineLimit(1)
                .frame(maxWidth: theme.sizes.toolPane, alignment: .leading)
            Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.tx3) }
                .buttonStyle(.plain).help(appString("removeFilter", "Remove filter"))
        }
        .padding(.leading, theme.spacing.s12).padding(.trailing, theme.spacing.s8).frame(height: theme.sizes.control32 - theme.spacing.s6)
        .background(highlighted ? c.sel : c.panel2, in: Capsule())
        .overlay { if theme.showOutline { Capsule().stroke(c.line, lineWidth: theme.borders.hairline) } }
    }
}
