import CoreDomain
import CoreUI
import SwiftUI

/// The title bar's search: a minimal global lookup over every synced ticket of the active workspace, by key or title
/// (the Flutter title bar has no such field; the Swift one was a dead box). ↑ / ↓ + Return or a click open the ticket in the
/// detail panel, Esc clears, ⌘K (when no board has its own search on screen) focuses it.
///
/// On a place with a search of its own (the Chat page, `PlaceSearch`) it lists that place's hits instead: clicked while
/// empty it offers the last searches and places; a "Show all" row lists every match.
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
    /// Every match was asked for ("Show all"), until the text changes.
    @State private var all = false
    /// The tab picked over the results ("" until one is: the place's first), and the choice made in each of its menus.
    @State private var scope = ""
    @State private var chosen: [String: String] = [:]
    @FocusState private var focused: Bool

    /// The place on screen's own search (the Chat page), if it has one.
    private var place: PlaceSearch? { model.host.placeSearch(model.nav.state.rail) }
    private var count: Int { place == nil ? results.count : hits.count }
    /// The tab the search is on: the one picked, else the place's first ("all").
    private var scopeId: String? { scope.isEmpty ? place?.scopes.first?.id : scope }
    /// A tab other than the first narrows the search, which then has something to list with nothing typed.
    private var narrowed: Bool { scopeId != place?.scopes.first?.id }
    private var typed: String { text.trimmingCharacters(in: .whitespaces) }

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
                .onKeyPress(.tab) { nextScope() }
            if text.isEmpty {
                Text(verbatim: "⌘K").font(theme.typography.caption).foregroundStyle(c.tx3)
            } else {
                Button(action: clear) { Image(systemName: "xmark.circle.fill").foregroundStyle(c.tx3) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, theme.spacing.s12)
        .onChange(of: text) { _, q in all = false; search(q) }
        .onChange(of: focused) { _, on in focusChanged(on) }
        .onChange(of: scope) { _, _ in all = false; search(text) }
        .onChange(of: chosen) { _, _ in all = false; search(text) }
        .onChange(of: model.searchFocusTick) { _, _ in focused = true; search(text) }
        // Another place searches other things: start over.
        .onChange(of: model.nav.state.rail) { _, _ in clear(); scope = ""; chosen = [:] }
        .task { model.detail.start() }
        .overlay(alignment: .topTrailing) {
            if showing {
                Group {
                    if let place {
                        PlaceSearchResults(place: place, hits: hits, highlight: highlight, searching: searching, offering: typed.isEmpty && !narrowed,
                                           scope: Binding(get: { scopeId ?? "" }, set: { scope = $0; focused = true }),
                                           chosen: Binding(get: { chosen }, set: { chosen = $0; focused = true }), onSelect: pick, onExtra: extra)
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
        guard !q.isEmpty || (place != nil && narrowed) else {
            results = []; hits = []; showing = false; searching = false
            if focused { suggest() }
            return
        }
        if let place {
            showing = true; searching = true
            let request = PlaceSearchRequest(query: q, all: all, scope: scopeId, options: chosen)
            // A moment after the last key, so typing does not search on every letter.
            placeTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                let found = await place.search(request)
                guard !Task.isCancelled else { return }
                hits = found; highlight = q.isEmpty ? -1 : 0; searching = false
            }
            return
        }
        let mine = Set(model.workspaceAccounts.map(\.id))
        results = SearchLocalTickets()(tickets: model.detail.tickets.values.filter { mine.contains($0.accountId) }, query: q)
        highlight = 0; showing = true
    }

    /// Clicked while empty: what the place offers before anything is typed (nothing highlighted, so Return opens nothing).
    private func suggest() {
        guard let place else { return }
        placeTask?.cancel()
        placeTask = Task { @MainActor in
            let offered = await place.suggestions()
            guard !Task.isCancelled, typed.isEmpty, focused else { return }
            // With tabs to pick from there is something to show even when nothing is offered.
            hits = offered; highlight = -1; showing = !offered.isEmpty || !place.scopes.isEmpty
        }
    }

    /// Tab steps through the search's tabs while its results are showing.
    private func nextScope() -> KeyPress.Result {
        guard showing, let scopes = place?.scopes, scopes.count > 1, let at = scopes.firstIndex(where: { $0.id == scopeId }) else { return .ignored }
        scope = scopes[(at + 1) % scopes.count].id
        return .handled
    }

    /// The small button at the end of a result: what it does closes the search, as opening the result does.
    private func extra(_ hit: PlaceSearchHit) {
        if !typed.isEmpty { place?.remember(typed) }
        hit.extra?.run()
        clear(); focused = false
    }

    private func focusChanged(_ on: Bool) {
        guard typed.isEmpty, !narrowed else { return }
        if on { suggest(); return }
        // A click on one of the suggestions (or a tab) takes the focus first: they stay long enough for it to land.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            if !focused, text.isEmpty, !narrowed { placeTask?.cancel(); hits = []; showing = false }
        }
    }

    private func move(_ d: Int) -> KeyPress.Result {
        guard count > 0 else { return .ignored }
        highlight = highlight < 0 ? (d > 0 ? 0 : count - 1) : (highlight + d + count) % count
        return .handled
    }

    private func clear() { placeTask?.cancel(); text = ""; scope = ""; results = []; hits = []; showing = false; searching = false; all = false }

    private func pick(_ hit: PlaceSearchHit) {
        switch hit.action {
        case .open(let go):
            let searched = text.trimmingCharacters(in: .whitespaces)
            if !searched.isEmpty { place?.remember(searched) }
            go()
            clear(); focused = false
        case .fill(let query):
            text = query; focused = true
        case .showAll:
            all = true; focused = true
            search(text)
        }
    }

    /// Goes to the ticket's account (so the panel sits over its own place) and opens it.
    private func open(_ t: Ticket) {
        if model.nav.state.rail != .account(t.accountId) { model.nav.select(.account(t.accountId)) }
        model.nav.openTicket(t.id)
        clear(); focused = false
    }
}
