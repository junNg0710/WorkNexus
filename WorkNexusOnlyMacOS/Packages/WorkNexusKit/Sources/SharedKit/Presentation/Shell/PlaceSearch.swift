/// Not in the Flutter app.
import CoreUI
import SwiftUI

/// What the title bar's search looks through on a place that has its own (the Chat page: chats and messages) instead of
/// the workspace's tickets. The app provides it (`ShellHost.placeSearch`); the shell knows nothing of chat.
public struct PlaceSearch {
    public var placeholder: String
    public var search: @MainActor (String) async -> [PlaceSearchHit]
    public init(placeholder: String, search: @escaping @MainActor (String) async -> [PlaceSearchHit]) {
        self.placeholder = placeholder; self.search = search
    }
}

public struct PlaceSearchHit: Identifiable {
    public var id: String
    /// The group it is listed under ("Chats", "Messages").
    public var section: String
    public var icon: String
    public var title: String
    public var subtitle: String
    public var detail: String
    public var open: () -> Void
    public init(id: String, section: String, icon: String, title: String, subtitle: String, detail: String = "", open: @escaping () -> Void) {
        self.id = id; self.section = section; self.icon = icon; self.title = title; self.subtitle = subtitle; self.detail = detail; self.open = open
    }
}

/// The results under the title bar's search on such a place: grouped, the highlighted one marked; a click opens it.
struct PlaceSearchResults: View {
    @Environment(\.appTheme) private var theme
    let hits: [PlaceSearchHit]
    let highlight: Int
    let searching: Bool
    let onSelect: (PlaceSearchHit) -> Void

    var body: some View {
        let c = theme.colors
        AppPopupCard {
            if hits.isEmpty {
                Text(searching ? appString("searching", "Searching…") : appString("searchNoResults", "No results found"))
                    .font(theme.typography.meta).foregroundStyle(c.tx3).frame(maxWidth: .infinity).padding(theme.spacing.s14)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                            if i == 0 || hits[i - 1].section != hit.section {
                                Text(hit.section).font(theme.typography.caption).foregroundStyle(c.tx3)
                                    .padding(.horizontal, theme.spacing.s8).padding(.top, i == 0 ? theme.spacing.s4 : theme.spacing.s10)
                                    .padding(.bottom, theme.spacing.s4)
                            }
                            HoverSurface(onTap: { onSelect(hit) }, selected: i == highlight, cornerRadius: theme.radii.sm) {
                                HStack(alignment: .top, spacing: theme.spacing.s8) {
                                    Image(systemName: hit.icon).font(.system(size: theme.sizes.icon14)).foregroundStyle(c.tx2).frame(width: 18)
                                    VStack(alignment: .leading, spacing: theme.spacing.s2) {
                                        HStack {
                                            Text(hit.title).font(theme.typography.metaStrong).foregroundStyle(c.tx).lineLimit(1)
                                            Spacer(minLength: theme.spacing.s8)
                                            Text(hit.detail).font(theme.typography.caption).foregroundStyle(c.tx3)
                                        }
                                        if !hit.subtitle.isEmpty {
                                            Text(hit.subtitle).font(theme.typography.meta).foregroundStyle(c.tx2).lineLimit(2)
                                        }
                                    }
                                }
                                .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s6)
                            }
                            .id(hit.id)
                        }
                    }
                    .padding(theme.spacing.s4)
                }
                .frame(maxHeight: 420)
            }
        }
    }
}
