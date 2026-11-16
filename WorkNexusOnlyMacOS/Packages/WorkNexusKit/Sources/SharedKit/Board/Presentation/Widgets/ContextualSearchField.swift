import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/{contextual_search_field,search_trailing_affordance}.dart
/// The toolbar's quick search over cached tickets in scope: debounced (150 ms), ↑/↓ + Return to open one, Esc to
/// clear, ⌘K to focus. Results appear under the field in `SearchResultsOverlay`.
public struct ContextualSearchField: View {
    @Environment(\.appTheme) private var theme
    let controller: BoardController; let scope: String?
    @State private var text = ""
    @State private var results: [Ticket] = []
    @State private var highlight = 0
    @State private var showing = false
    @State private var debounce: Task<Void, Never>?
    @State private var overlayHeight: CGFloat = 0
    @FocusState private var focused: Bool
    @Environment(\.sectionIsActive) private var sectionActive

    public init(controller: BoardController, scope: String? = nil) { self.controller = controller; self.scope = scope }

    private func changed(_ query: String) {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }
            let q = query.trimmingCharacters(in: .whitespaces)
            if q.isEmpty { results = []; highlight = 0; showing = false; return }
            results = controller.search(q); highlight = 0; showing = true
        }
    }

    private func open(_ t: Ticket) { controller.openTicket(t.id); text = ""; showing = false; results = []; focused = false }

    public var body: some View {
        let c = theme.colors
        HStack(spacing: theme.spacing.s6) {
            Image(systemName: "magnifyingglass").font(.system(size: theme.sizes.icon14)).foregroundStyle(c.tx3)
            TextField(scope.map { appFormat("searchContextTool", "Search in %1$@…", $0) } ?? appString("search", "Search"), text: $text)
                .textFieldStyle(.plain).font(theme.typography.meta).focused($focused)
                .onChange(of: text) { _, v in changed(v) }
                .onSubmit { if results.indices.contains(highlight) { open(results[highlight]) } }
                .onKeyPress(.downArrow) { if !results.isEmpty { highlight = (highlight + 1) % results.count }; return .handled }
                .onKeyPress(.upArrow) { if !results.isEmpty { highlight = (highlight - 1 + results.count) % results.count }; return .handled }
                .onKeyPress(.escape) { if text.isEmpty { focused = false } else { text = "" }; showing = false; return .handled }
            if text.isEmpty {
                Text("⌘K").font(theme.typography.mono).foregroundStyle(c.tx3)
                    .padding(.horizontal, theme.spacing.s4)
                    .background(c.panel2, in: RoundedRectangle(cornerRadius: theme.radii.xs))
            } else {
                Button { text = "" } label: { Image(systemName: "xmark").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.tx3) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, theme.spacing.s6).frame(height: theme.sizes.control32)
        .background(c.panel, in: RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(c.line, lineWidth: theme.borders.hairline))
        .background {
            Button("") { focused = true; if !text.trimmingCharacters(in: .whitespaces).isEmpty { showing = true } }
                .keyboardShortcut("k", modifiers: .command).opacity(0).frame(width: 0, height: 0)
        }
        .overlay(alignment: .topLeading) {
            if showing {
                SearchResultsOverlay(results: results, highlight: highlight, registry: controller.registry, onSelect: open)
                    .frame(width: 480).onGeometryChange(for: CGFloat.self) { $0.size.height } action: { overlayHeight = $0 }
                    .offset(y: theme.sizes.control32 + theme.spacing.s4).zIndex(10)
            }
        }
        .zIndex(showing ? 10 : 0)
        // A click outside the field and its results closes them (the typed text stays).
        .onOutsideClick(isActive: showing, extra: CGRect(x: 0, y: theme.sizes.control32 + theme.spacing.s4, width: 480, height: overlayHeight)) { showing = false }
        // The menu's ⌘K reaches the board on screen first (a hidden, kept-alive board must not answer it).
        .focusedSceneValue(\.boardSearch, sectionActive ? { focused = true; if !text.trimmingCharacters(in: .whitespaces).isEmpty { showing = true } } : nil)
    }
}

/// Ported from: lib/shared/board/presentation/widgets/search_results_overlay.dart
public struct SearchResultsOverlay: View {
    @Environment(\.appTheme) private var theme
    let results: [Ticket]; let highlight: Int; let registry: ToolRegistry; let onSelect: (Ticket) -> Void

    public init(results: [Ticket], highlight: Int, registry: ToolRegistry, onSelect: @escaping (Ticket) -> Void) {
        self.results = results; self.highlight = highlight; self.registry = registry; self.onSelect = onSelect
    }

    public var body: some View {
        let c = theme.colors
        AppPopupCard {
            if results.isEmpty {
                Text(appString("searchNoResults", "No results found")).font(theme.typography.meta).foregroundStyle(c.tx3)
                    .frame(maxWidth: .infinity).padding(theme.spacing.s14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, t in
                        if i > 0 { Divider().overlay(c.line) }
                        HoverSurface(onTap: { onSelect(t) }, selected: i == highlight, cornerRadius: theme.radii.sm) {
                            HStack(spacing: theme.spacing.s6) {
                                BrandLogoBadge(t.providerType, size: 15)
                                Text(t.externalKey).font(theme.typography.mono.weight(.semibold)).foregroundStyle(c.tx2).lineLimit(1)
                                    .frame(width: 80, alignment: .leading)
                                Text(t.title).font(theme.typography.meta).foregroundStyle(c.tx).lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                TicketStatusPill(ticket: t, registry: registry)
                            }
                            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s6)
                        }
                    }
                }
                .padding(theme.spacing.s4)
            }
        }
    }
}
