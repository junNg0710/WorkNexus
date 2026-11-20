import SwiftUI

/// Ported from: lib/core/widgets/searchable_dropdown_field.dart (+ .parts / .leaves)
/// A themed select field with a filterable popover list. Renders like the app's input fields when closed;
/// clicking opens an anchored popover with a search box and a scrollable, keyboard-navigable list of `items`
/// (↑ / ↓ move, Return picks, Esc closes). `searchTextOf` is the text matched against the query (default: the label);
/// `imageOf` puts a small picture before each option (an app's icon).
public struct SearchableDropdownField<T: Hashable>: View {
    @Environment(\.appTheme) private var theme
    @State private var open = false
    @State private var query = ""
    @State private var highlighted = 0
    @State private var fieldWidth: CGFloat = 260
    /// One option row as drawn, measured: the list's height is worked out from it.
    @State private var rowHeight: CGFloat = 30
    let items: [T]; let value: T?; let onChanged: (T) -> Void; let labelOf: (T) -> String
    let searchTextOf: ((T) -> String)?
    let hintText: String; let searchHint: String; let emptyLabel: String
    let maxListHeight: CGFloat; let popoverMinWidth: CGFloat?; let labelMaxLines: Int
    let imageOf: ((T) -> Image?)?

    public init(items: [T], value: T?, labelOf: @escaping (T) -> String, searchTextOf: ((T) -> String)? = nil,
                hintText: String = "Select…", searchHint: String = "Search…", emptyLabel: String = "No matches",
                maxListHeight: CGFloat = 260, popoverMinWidth: CGFloat? = nil, labelMaxLines: Int = 1,
                imageOf: ((T) -> Image?)? = nil, onChanged: @escaping (T) -> Void) {
        self.items = items; self.value = value; self.labelOf = labelOf; self.searchTextOf = searchTextOf
        self.hintText = hintText; self.searchHint = searchHint; self.emptyLabel = emptyLabel
        self.maxListHeight = maxListHeight; self.popoverMinWidth = popoverMinWidth; self.labelMaxLines = labelMaxLines
        self.imageOf = imageOf
        self.onChanged = onChanged
    }

    private var filtered: [T] {
        guard !query.isEmpty else { return items }
        let q = query.lowercased()
        return items.filter { (searchTextOf ?? labelOf)($0).lowercased().contains(q) }
    }

    public var body: some View {
        Button { toggle() } label: {
            HStack(spacing: theme.spacing.s6) {
                Text(value.map(labelOf) ?? hintText).font(theme.typography.body)
                    .foregroundStyle(value == nil ? theme.colors.tx3 : theme.colors.tx).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx2)
            }
            .padding(.horizontal, theme.spacing.s12).frame(height: theme.sizes.control32).frame(maxWidth: .infinity)
            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(open ? theme.colors.accent : theme.colors.line, lineWidth: theme.borders.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { fieldWidth = $0 }
        .popover(isPresented: $open, arrowEdge: .bottom) { popover }
    }

    private func toggle() {
        query = ""
        highlighted = value.flatMap { items.firstIndex(of: $0) } ?? 0
        open.toggle()
    }

    private func pick(_ item: T) { open = false; onChanged(item) }

    /// The list keeps the height of every item (up to `maxListHeight`) while a search narrows it: the popover would
    /// otherwise shrink to the matches and stay small once the search is cleared.
    private var listHeight: CGFloat {
        min(maxListHeight, CGFloat(max(items.count, 1)) * rowHeight + theme.spacing.s4 * 2)
    }

    private var popover: some View {
        let list = filtered
        return VStack(spacing: 0) {
            AppSearchField(text: $query, hint: searchHint, autofocus: true,
                           onSubmit: { if list.indices.contains(highlighted) { pick(list[highlighted]) } },
                           onMove: { highlighted = min(max(highlighted + $0, 0), max(list.count - 1, 0)) })
                .padding(theme.spacing.s8)
            Divider().overlay(theme.colors.line)
            if list.isEmpty {
                Text(emptyLabel).font(theme.typography.body).foregroundStyle(theme.colors.tx3).padding(theme.spacing.s16)
                    .frame(maxWidth: .infinity, minHeight: listHeight, alignment: .top)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.offset) { i, item in
                                DropdownOptionRow(label: labelOf(item), image: imageOf?(item), selected: item == value,
                                                  highlighted: i == highlighted, lines: labelMaxLines) { pick(item) }
                                    .id(i)
                                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
                                        if i == 0, h > 0, abs(h - rowHeight) >= 1 { rowHeight = h }
                                    }
                            }
                        }.padding(theme.spacing.s4)
                    }
                    .frame(height: listHeight)
                    .onChange(of: highlighted) { _, new in proxy.scrollTo(new) }
                }
            }
        }
        .frame(width: max(fieldWidth, popoverMinWidth ?? 0))
        .background(theme.colors.card)
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onExitCommand { open = false }
    }
}

private struct DropdownOptionRow: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let label: String; let image: Image?; let selected: Bool; let highlighted: Bool; let lines: Int; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.s8) {
                if let image { image.resizable().interpolation(.high).frame(width: theme.sizes.icon16, height: theme.sizes.icon16) }
                Text(label).font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(lines).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.accent) }
            }
            .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s6)
            .background(highlighted || hovering ? theme.colors.sel : .clear, in: RoundedRectangle(cornerRadius: theme.radii.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
    }
}
