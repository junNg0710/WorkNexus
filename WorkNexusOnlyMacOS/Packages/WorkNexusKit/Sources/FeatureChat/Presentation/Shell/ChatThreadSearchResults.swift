/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SwiftUI

/// "Sent by": narrows the in-chat search to one of the people whose messages it found.
struct ChatSearchSenderButton: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let search: ChatThreadSearch

    var body: some View {
        AppMenuButton(help: shellString("chatSearchSentBy", "Sent by"), items: {
            [AppNativeMenu.Item(shellString("chatSearchAnyone", "Anyone"), icon: "person.2", checked: search.sender == nil) { search.setSender(nil) }]
                + search.senders.map { id in
                    AppNativeMenu.Item(ChatTextLabels.userName(model.users, id), icon: "person", checked: search.sender == id) { search.setSender(id) }
                }
        }) {
            Label(search.sender.map { ChatTextLabels.userName(model.users, $0) } ?? shellString("chatSearchAnyone", "Anyone"), systemImage: "person")
                .font(theme.typography.meta).foregroundStyle(search.sender == nil ? theme.colors.tx2 : theme.colors.accent).lineLimit(1)
        }
        .fixedSize()
    }
}

/// The matches of the in-chat search as a list under its bar: who said it, when, and the line the words are found in
/// (marked). A click goes to the message; the one the list is on is highlighted.
struct ChatThreadSearchResults: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let search: ChatThreadSearch
    private static let maxHeight: CGFloat = 260

    var body: some View {
        let terms = SearchTerms.parse(search.query)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(search.matches.enumerated()), id: \.element.gid) { i, m in
                        HoverSurface(onTap: { search.show(i) }, selected: i == search.activeIndex, cornerRadius: theme.radii.sm) {
                            ChatSearchResultRow(who: ChatTextLabels.userName(model.users, m.senderId), when: ChatShellLabels.listTime(m.sentAt),
                                                said: SearchTerms.snippet(ChatShellLabels.preview(m), terms: terms, length: 160), terms: terms)
                        }
                        .id(m.gid)
                    }
                }
                .padding(theme.spacing.s4)
            }
            .frame(maxHeight: Self.maxHeight)
            .onChange(of: search.activeIndex) { _, at in if search.matches.indices.contains(at) { proxy.scrollTo(search.matches[at].gid) } }
        }
        .background(theme.colors.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
    }
}

private struct ChatSearchResultRow: View {
    @Environment(\.appTheme) private var theme
    let who: String
    let when: String
    let said: String
    let terms: [String]

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: theme.spacing.s2) {
            HStack {
                Text(who).font(theme.typography.metaStrong).foregroundStyle(c.tx).lineLimit(1)
                Spacer(minLength: theme.spacing.s8)
                Text(when).font(theme.typography.caption).foregroundStyle(c.tx3)
            }
            Text(marked).font(theme.typography.meta).foregroundStyle(c.tx2).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s6)
    }

    private var marked: AttributedString {
        var found = AttributeContainer()
        found.foregroundColor = theme.colors.tx
        found.backgroundColor = theme.colors.accent.opacity(0.22)
        return .marked(said, terms, with: found)
    }
}
