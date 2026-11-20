import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/{filter_dropdown_group,filter_people_block}.dart
/// A multi-select dropdown: a field showing the picks, opening a searchable checklist.
public struct FilterDropdownGroup: View {
    @Environment(\.appTheme) private var theme
    let label: String; let options: [FilterChipOption]; var dense = false
    @State private var open = false
    @State private var query = ""

    public init(label: String, options: [FilterChipOption], dense: Bool = false) { self.label = label; self.options = options; self.dense = dense }

    private var visible: [FilterChipOption] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? options : options.filter { $0.active || $0.label.lowercased().contains(q) }
    }

    public var body: some View {
        let c = theme.colors
        let picked = options.filter(\.active)
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            AppSectionHeader(label)
            HoverSurface(onTap: { open.toggle(); if !open { query = "" } }, height: theme.sizes.control32,
                         fill: picked.isEmpty ? c.panel : c.sel, border: theme.showOutline ? c.line : nil) {
                HStack(spacing: theme.spacing.s6) {
                    Text(picked.isEmpty ? appString("filterAnyOption", "Any") : picked.map(\.label).joined(separator: ", "))
                        .font(theme.typography.meta).foregroundStyle(picked.isEmpty ? c.tx3 : c.tx).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !picked.isEmpty { AppCountBadge(picked.count) }
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.tx2)
                }
                .padding(.horizontal, theme.spacing.s8)
            }
            if open {
                AppSearchField(text: $query, hint: appString("filterSearchHint", "Search…"), height: theme.sizes.control32 - theme.spacing.s6)
                ScrollView {
                    VStack(spacing: 0) {
                        if visible.isEmpty {
                            Text(appString("filterNoMatches", "No option matches")).font(theme.typography.meta).foregroundStyle(c.tx3)
                                .padding(theme.spacing.s6)
                        }
                        ForEach(visible) { FilterOptionRow(option: $0) }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(.bottom, dense ? 0 : theme.spacing.s14)
    }
}

private struct FilterOptionRow: View {
    @Environment(\.appTheme) private var theme
    let option: FilterChipOption
    var body: some View {
        let c = theme.colors
        HoverSurface(onTap: option.onTap, selected: option.active, height: theme.sizes.control32 - theme.spacing.s6, cornerRadius: theme.radii.sm) {
            HStack(spacing: theme.spacing.s6) {
                Image(systemName: option.active ? "checkmark.square.fill" : "square").font(.system(size: theme.sizes.icon14))
                    .foregroundStyle(option.active ? c.accent : c.tx3)
                if let dot = option.dotColor { Circle().fill(dot).frame(width: theme.spacing.s6, height: theme.spacing.s6) }
                Text(option.label).font(theme.typography.meta).foregroundStyle(option.active ? c.tx : c.tx2).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let n = option.count { Text(verbatim: "\(n)").font(theme.typography.meta).foregroundStyle(c.tx3) }
            }
            .padding(.horizontal, theme.spacing.s6)
        }
    }
}

/// People filters (assignee / resolved by / opened by) joined as one OR box: a ticket shows when any matches.
public struct FilterPeopleBlock: View {
    @Environment(\.appTheme) private var theme
    let groups: [(label: String, options: [FilterChipOption])]
    public init(groups: [(label: String, options: [FilterChipOption])]) { self.groups = groups }

    public var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            AppSectionHeader(appString("filterPeople", "People")) { OrTag() }
            Text(appString("filterPeopleAnyHint", "A ticket shows when any one of these matches"))
                .font(theme.typography.meta).foregroundStyle(c.tx3)
            ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                if i > 0 {
                    HStack(spacing: theme.spacing.s6) {
                        Rectangle().fill(c.line).frame(height: 1); OrTag(); Rectangle().fill(c.line).frame(height: 1)
                    }
                    .padding(.vertical, theme.spacing.s6)
                }
                FilterDropdownGroup(label: g.label, options: g.options, dense: true)
            }
        }
        .padding(theme.spacing.s8)
        .background(c.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay { if theme.showOutline { RoundedRectangle(cornerRadius: theme.radii.md).stroke(c.line, lineWidth: theme.borders.hairline) } }
        .padding(.bottom, theme.spacing.s14)
    }
}

private struct OrTag: View {
    @Environment(\.appTheme) private var theme
    var body: some View {
        Text(appString("filterOr", "OR")).font(theme.typography.caption.weight(.semibold)).foregroundStyle(theme.colors.accent)
            .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s2)
            .background(theme.colors.sel, in: Capsule())
    }
}
