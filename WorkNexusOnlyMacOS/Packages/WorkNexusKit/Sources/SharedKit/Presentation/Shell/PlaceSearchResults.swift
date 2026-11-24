/// Not in the Flutter app.
import CoreUI
import SwiftUI

/// What hangs under the title bar's search on a place with a search of its own: the tabs and menus that narrow it, the
/// results grouped (the highlighted one marked; a click picks it), and a line saying what is searched.
struct PlaceSearchResults: View {
    @Environment(\.appTheme) private var theme
    let place: PlaceSearch
    let hits: [PlaceSearchHit]
    let highlight: Int
    let searching: Bool
    /// Nothing typed and nothing narrowed: only what the place offers is listed, and an empty list says nothing.
    let offering: Bool
    @Binding var scope: String
    @Binding var chosen: [String: String]
    let onSelect: (PlaceSearchHit) -> Void
    let onExtra: (PlaceSearchHit) -> Void
    /// How tall the rows are together: the list is that tall, up to `maxHeight`. (Hanging under the search field it is
    /// offered the field's own height, which a scroll view takes as it is - the results showed as a sliver.)
    @State private var rowsHeight: CGFloat = 0
    private static let maxHeight: CGFloat = 420

    var body: some View {
        let c = theme.colors
        AppPopupCard {
            VStack(alignment: .leading, spacing: 0) {
                if !place.scopes.isEmpty || !place.options.isEmpty {
                    PlaceSearchNarrowing(place: place, scope: $scope, chosen: $chosen)
                    Rectangle().fill(c.line).frame(height: theme.borders.hairline)
                }
                if hits.isEmpty {
                    if !offering || searching {
                        Text(searching ? appString("searching", "Searching…") : appString("searchNoResults", "No results found"))
                            .font(theme.typography.meta).foregroundStyle(c.tx3).frame(maxWidth: .infinity).padding(theme.spacing.s14)
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            // Lazy: every match of a search can be hundreds of rows.
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                                    if i == 0 || hits[i - 1].section != hit.section {
                                        Text(hit.section).font(theme.typography.caption).foregroundStyle(c.tx3)
                                            .padding(.horizontal, theme.spacing.s8).padding(.top, i == 0 ? theme.spacing.s4 : theme.spacing.s10)
                                            .padding(.bottom, theme.spacing.s4)
                                    }
                                    HoverSurface(onTap: { onSelect(hit) }, selected: i == highlight, cornerRadius: theme.radii.sm) {
                                        PlaceSearchRow(hit: hit, onExtra: { onExtra(hit) })
                                    }
                                    .id(hit.id)
                                }
                            }
                            .padding(theme.spacing.s4)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
                        }
                        .frame(height: min(max(rowsHeight, theme.sizes.control36), Self.maxHeight))
                        // The arrow keys can step past what is in view.
                        .onChange(of: highlight) { _, at in if hits.indices.contains(at) { proxy.scrollTo(hits[at].id) } }
                    }
                }
                if let note = place.note, !offering || !hits.isEmpty {
                    Rectangle().fill(c.line).frame(height: theme.borders.hairline)
                    // Its own height: hanging under the field it is offered one line's worth, and was cut short.
                    Text(note).font(theme.typography.caption).foregroundStyle(c.tx3).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s6)
                }
            }
            // Glass alone let a chat's wallpaper and pictures show through the results.
            .background(c.panel.opacity(0.88))
        }
    }
}

/// The tabs that narrow a search to one kind of thing, and the menus for what else narrows it.
private struct PlaceSearchNarrowing: View {
    @Environment(\.appTheme) private var theme
    let place: PlaceSearch
    @Binding var scope: String
    @Binding var chosen: [String: String]

    var body: some View {
        let c = theme.colors
        HStack(spacing: theme.spacing.s4) {
            ForEach(place.scopes) { s in
                let on = s.id == scope
                Button { scope = s.id } label: {
                    Text(s.title).font(on ? theme.typography.metaStrong : theme.typography.meta).foregroundStyle(on ? c.accent : c.tx2)
                        .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s4)
                        .background(on ? c.accent.opacity(0.14) : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: theme.spacing.s8)
            ForEach(place.options) { option in
                let picked = chosen[option.id] ?? option.choices.first?.id
                AppMenuButton(help: option.help, items: {
                    option.choices.map { choice in AppNativeMenu.Item(choice.title, checked: choice.id == picked) { chosen[option.id] = choice.id } }
                }) {
                    Label(option.choices.first { $0.id == picked }?.title ?? "", systemImage: option.icon)
                        .font(theme.typography.meta).foregroundStyle(c.tx2)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s6)
    }
}

/// One result: its picture or icon, the title with the time, and what was found under it - the words searched marked.
private struct PlaceSearchRow: View {
    @Environment(\.appTheme) private var theme
    let hit: PlaceSearchHit
    let onExtra: () -> Void

    var body: some View {
        let c = theme.colors
        if hit.showsAll {
            Text(hit.title).font(theme.typography.metaStrong).foregroundStyle(c.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s6)
        } else {
            HStack(alignment: hit.subtitle.isEmpty && hit.lead.isEmpty ? .center : .top, spacing: theme.spacing.s8) {
                if let leading = hit.leading { leading } else {
                    Image(systemName: hit.icon).font(.system(size: theme.sizes.icon14)).foregroundStyle(c.tx2).frame(width: theme.sizes.icon18)
                }
                VStack(alignment: .leading, spacing: theme.spacing.s2) {
                    HStack {
                        Text(hit.marksTitle ? marked(hit.title) : AttributedString(hit.title)).font(theme.typography.metaStrong)
                            .foregroundStyle(c.tx).lineLimit(1)
                        Spacer(minLength: theme.spacing.s8)
                        Text(hit.detail).font(theme.typography.caption).foregroundStyle(c.tx3)
                    }
                    if !hit.subtitle.isEmpty || !hit.lead.isEmpty {
                        Text(AttributedString(hit.lead) + marked(hit.subtitle)).font(theme.typography.meta).foregroundStyle(c.tx2).lineLimit(2)
                    }
                }
                if let extra = hit.extra {
                    AppIconButton(extra.icon, help: extra.help, action: onExtra)
                }
            }
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s6)
        }
    }

    /// `text` with the words searched standing out: the accent's tint behind them, in the full text colour.
    private func marked(_ text: String) -> AttributedString {
        var found = AttributeContainer()
        found.foregroundColor = theme.colors.tx
        found.backgroundColor = theme.colors.accent.opacity(0.22)
        return .marked(text, hit.marks, with: found)
    }
}
