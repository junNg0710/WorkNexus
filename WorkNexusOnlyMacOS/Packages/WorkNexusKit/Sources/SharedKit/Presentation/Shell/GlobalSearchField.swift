import CoreDomain
import CoreUI
import SwiftUI

/// The title bar's search: a minimal global lookup over every synced ticket of the active workspace, by key or title
/// (the Flutter title bar has no such field; the Swift one was a dead box). ↑ / ↓ + Return or a click open the ticket in the
/// detail panel, Esc clears, ⌘K (when no board has its own search on screen) focuses it.
struct GlobalSearchField: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel
    @State private var text = ""
    @State private var results: [Ticket] = []
    @State private var highlight = 0
    @State private var showing = false
    @State private var hits: [PlaceSearchHit] = []
    @State private var searching = false
    @State private var placeTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    /// The place on screen's own search (the Chat page), if it has one.
    private var place: PlaceSearch? { model.host.placeSearch(model.nav.state.rail) }
    private var count: Int { place == nil ? results.count : hits.count }

    var body: some View {
        let c = theme.colors
        HStack(spacing: theme.spacing.s6) {
            Image(systemName: "magnifyingglass").foregroundStyle(c.tx3)
            TextField(place?.placeholder ?? appString("search", "Search tasks, IDs, projects…"), text: $text)
                .textFieldStyle(.plain).font(theme.typography.body).focused($focused)
                .onSubmit {
                    if place != nil { if hits.indices.contains(highlight) { pick(hits[highlight]) } }
                    else if results.indices.contains(highlight) { open(results[highlight]) }
                }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.escape) { clear(); focused = false; return .handled }
            if text.isEmpty {
                Text(verbatim: "⌘K").font(theme.typography.caption).foregroundStyle(c.tx3)
            } else {
                Button(action: clear) { Image(systemName: "xmark.circle.fill").foregroundStyle(c.tx3) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, theme.spacing.s12)
        .onChange(of: text) { _, q in search(q) }
        .onChange(of: model.searchFocusTick) { _, _ in focused = true; search(text) }
        // Another place searches other things: start over.
        .onChange(of: model.nav.state.rail) { _, _ in clear() }
        .task { model.detail.start() }
        .overlay(alignment: .topTrailing) {
            if showing {
                Group {
                    if place != nil {
                        PlaceSearchResults(hits: hits, highlight: highlight, searching: searching, onSelect: pick)
                    } else {
                        SearchResultsOverlay(results: results, highlight: highlight, registry: model.registry, onSelect: open)
                    }
                }
                .frame(width: theme.sizes.dialogMd + theme.spacing.s24)
                .offset(y: theme.sizes.control36 + theme.spacing.s4)
            }
        }
        .zIndex(showing ? 10 : 0)
    }

    private func search(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        placeTask?.cancel()
        guard !q.isEmpty else { results = []; hits = []; showing = false; return }
        if let place {
            showing = true; searching = true
            // A moment after the last key, so typing does not search on every letter.
            placeTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                let found = await place.search(q)
                guard !Task.isCancelled else { return }
                hits = found; highlight = 0; searching = false
            }
            return
        }
        let mine = Set(model.workspaceAccounts.map(\.id))
        results = SearchLocalTickets()(tickets: model.detail.tickets.values.filter { mine.contains($0.accountId) }, query: q)
        highlight = 0; showing = true
    }

    private func move(_ d: Int) -> KeyPress.Result {
        guard count > 0 else { return .ignored }
        highlight = (highlight + d + count) % count
        return .handled
    }

    private func clear() { placeTask?.cancel(); text = ""; results = []; hits = []; showing = false; searching = false }

    private func pick(_ hit: PlaceSearchHit) {
        hit.open()
        clear(); focused = false
    }

    /// Goes to the ticket's account (so the panel sits over its own place) and opens it.
    private func open(_ t: Ticket) {
        if model.nav.state.rail != .account(t.accountId) { model.nav.select(.account(t.accountId)) }
        model.nav.openTicket(t.id)
        clear(); focused = false
    }
}
