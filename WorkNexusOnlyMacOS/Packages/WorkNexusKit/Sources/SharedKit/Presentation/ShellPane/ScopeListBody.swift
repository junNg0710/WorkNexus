import CoreUI
import SwiftUI

/// Ported from: lib/shared/shell_pane/scope_list_body.dart
/// The scrolling body of a tool nav pane: quick-scope rows, then Pinned, Recent, and the full list (capped at `cap`
/// rows with a "Show all" button until expanded). `emptyPlaceholder` replaces everything when every list is empty.
public struct ScopeListBody: View {
    @Environment(\.appTheme) private var theme
    let quickScopeRows: [AnyView]; let pinnedRows: [AnyView]; let recentRows: [AnyView]; let allRows: [AnyView]
    let groupTitle: String?; let cap: Int; let showAllLabel: String?; let emptyPlaceholder: AnyView?
    @State private var expanded: Bool

    public init(quickScopeRows: [AnyView] = [], pinnedRows: [AnyView] = [], recentRows: [AnyView] = [], allRows: [AnyView] = [],
                groupTitle: String? = nil, cap: Int = 12, showAllLabel: String? = nil, initiallyExpanded: Bool = false,
                emptyPlaceholder: AnyView? = nil) {
        self.quickScopeRows = quickScopeRows; self.pinnedRows = pinnedRows; self.recentRows = recentRows; self.allRows = allRows
        self.groupTitle = groupTitle; self.cap = cap; self.showAllLabel = showAllLabel; self.emptyPlaceholder = emptyPlaceholder
        _expanded = State(initialValue: initiallyExpanded)
    }

    public var body: some View {
        let isEmpty = quickScopeRows.isEmpty && pinnedRows.isEmpty && recentRows.isEmpty && allRows.isEmpty
        if isEmpty, let emptyPlaceholder {
            emptyPlaceholder.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let capped = !expanded && allRows.count > cap
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.s2) {
                    if !quickScopeRows.isEmpty { ForEach(Array(quickScopeRows.enumerated()), id: \.offset) { $1 }; Color.clear.frame(height: theme.spacing.s4) }
                    if !pinnedRows.isEmpty {
                        ScopeGroupHeader(title: appString("pinned", "Pinned"))
                        ForEach(Array(pinnedRows.enumerated()), id: \.offset) { $1 }
                    }
                    if !recentRows.isEmpty {
                        ScopeGroupHeader(title: appString("recent", "Recent"))
                        ForEach(Array(recentRows.enumerated()), id: \.offset) { $1 }
                    }
                    if !allRows.isEmpty {
                        if let groupTitle { ScopeGroupHeader(title: groupTitle) }
                        ForEach(Array((capped ? Array(allRows.prefix(cap)) : allRows).enumerated()), id: \.offset) { $1 }
                        if capped { ShowAllScopesButton(label: showAllLabel ?? appString("showAll", "Show all")) { expanded = true } }
                    }
                }
                .padding(EdgeInsets(top: theme.spacing.s4, leading: theme.spacing.s6, bottom: theme.spacing.s12, trailing: theme.spacing.s6))
            }
        }
    }
}

public struct ShowAllScopesButton: View {
    @Environment(\.appTheme) private var theme
    let label: String; let onTap: () -> Void
    public init(label: String, onTap: @escaping () -> Void) { self.label = label; self.onTap = onTap }
    public var body: some View {
        HoverSurface(onTap: onTap, height: theme.sizes.control32 - theme.spacing.s6, cornerRadius: theme.radii.sm) {
            Text(label).font(theme.typography.meta.weight(.medium)).foregroundStyle(theme.colors.accent).lineLimit(1)
                .padding(.horizontal, theme.spacing.s6).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
