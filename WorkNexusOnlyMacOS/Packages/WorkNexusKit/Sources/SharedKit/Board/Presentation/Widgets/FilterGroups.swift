import CoreDomain
import CoreUI
import SwiftUI

/// A tool's own rendering of a status facet option (ZenTao shows its column names / colours).
public typealias FacetStatusOption = (_ option: BoardFacetOption, _ active: Bool, _ onTap: @escaping () -> Void) -> FilterChipOption

/// Ported from: lib/shared/board/presentation/widgets/filter_facet_groups.dart
/// Filter groups of the board's facets (people together as one OR block, the rest as chips or dropdowns).
public struct FacetFilterGroups: View {
    @Environment(\.appTheme) private var theme
    let controller: BoardController
    var statusOption: FacetStatusOption?; var catalog: BoardFacetCatalog?; var onPick: (() -> Void)?
    private static let people: Set<BoardFacetKind> = [.assignee, .resolvedBy, .openedBy]

    public init(controller: BoardController, statusOption: FacetStatusOption? = nil, catalog: BoardFacetCatalog? = nil,
                onPick: (() -> Void)? = nil) {
        self.controller = controller; self.statusOption = statusOption; self.catalog = catalog; self.onPick = onPick
    }

    private func options(_ g: BoardFacetGroup) -> [FilterChipOption] {
        let f = controller.filter
        return g.options.map { o in
            if g.kind == .status, let statusOption {
                return statusOption(o, f.zentaoStatuses.contains(o.value)) { controller.toggleFacet(.status, o.value); onPick?() }
            }
            return FilterChipOption(label: o.label ?? facetLabel(g.kind, o.value), active: facetActive(f, g.kind, o.value),
                                    onTap: { controller.toggleFacet(g.kind, o.value); onPick?() },
                                    dotColor: facetDot(theme.colors, g.kind, o.value), count: o.count > 0 ? o.count : nil)
        }
    }

    public var body: some View {
        let groups = controller.facets(catalog: catalog).groups.filter { $0.kind != .module }
        let people = groups.filter { Self.people.contains($0.kind) }
        let together = people.count > 1
        if groups.isEmpty {
            Text(appString("noBoardFilters", "No filters for this board")).font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(groups, id: \.kind) { g in
                    if together && g.kind == people.first?.kind {
                        FilterPeopleBlock(groups: people.map { (facetHeader($0.kind), options($0)) })
                    } else if !together || !Self.people.contains(g.kind) {
                        FilterOptionsGroup(label: facetHeader(g.kind), options: options(g),
                                           dropdownThreshold: Self.people.contains(g.kind) ? 0 : 8)
                    }
                }
            }
        }
    }
}

/// Ported from: lib/shared/board/presentation/widgets/filter_generic_groups.dart
/// Provider / account / project / status / priority groups for boards without facets.
public struct GenericFilterGroups: View {
    @Environment(\.appTheme) private var theme
    let controller: BoardController
    public init(controller: BoardController) { self.controller = controller }

    public var body: some View {
        let c = theme.colors
        let f = controller.filter
        let scope = controller.genericScope
        let providers = ProviderType.allCases.filter { scope.providers.contains($0) }
        let accounts = controller.accounts.values.filter { scope.accountIds.contains($0.id) }.sorted { $0.id < $1.id }
        let projects = controller.projects.values.filter { scope.projectIds.contains($0.id) }.sorted { $0.name < $1.name }
        VStack(alignment: .leading, spacing: 0) {
            FilterGroup(label: appString("provider", "Provider"), count: providers.count) {
                ForEach(providers, id: \.self) { p in
                    FilterOptionChip(FilterChipOption(label: p.displayName, active: f.providers.contains(p), onTap: { controller.toggleProvider(p) }))
                }
            }
            FilterOptionsGroup(label: appString("account", "Account"), options: accounts.map { a in
                let ws = controller.workspaces[a.workspaceId]
                return FilterChipOption(label: a.handle, active: f.accountIds.contains(a.id), onTap: { controller.toggleAccount(a.id) },
                                        dotColor: ws.map { Color(argb: UInt32(truncatingIfNeeded: $0.colorValue)) } ?? c.workspaceFallback)
            })
            FilterOptionsGroup(label: appString("project", "Project"), options: projects.map { p in
                FilterChipOption(label: p.name, active: f.projectIds.contains(p.id), onTap: { controller.toggleProject(p.id) })
            })
            if !controller.isMineBoard {
                FilterGroup(label: appString("status", "Status"), count: UnifiedStatus.columns.count) {
                    ForEach(UnifiedStatus.columns, id: \.self) { s in
                        FilterOptionChip(FilterChipOption(label: statusLabel(s), active: f.statuses.contains(s), onTap: { controller.toggleStatus(s) },
                                                          dotColor: c.statusColor(s)))
                    }
                }
                FilterGroup(label: appString("priority", "Priority"), count: Priority.allCases.count) {
                    ForEach(Priority.allCases, id: \.self) { p in
                        FilterOptionChip(FilterChipOption(label: priorityName(p), active: f.priorities.contains(p), onTap: { controller.togglePriority(p) },
                                                          dotColor: c.priorityColor(p)))
                    }
                }
            }
        }
    }
}
