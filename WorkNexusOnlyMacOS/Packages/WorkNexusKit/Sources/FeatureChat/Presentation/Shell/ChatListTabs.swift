import CoreDomain
import CoreUI
import SwiftUI

/// Filter chips above the chat list: all, direct, groups, bots — each with the unread count of the chats it shows.
/// Ported from: lib/features/chat/presentation/widgets/chat_list_tabs.dart
struct ChatListTabs: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.s6) {
                ForEach(ChatListTab.allCases, id: \.self) { tab in
                    ChatTabChip(label: Self.label(tab), selected: tab == model.tab, unread: model.unread(tab)) { model.tab = tab }
                }
            }
            .padding(.horizontal, theme.spacing.s12)
        }
        .frame(height: theme.sizes.control32)
    }

    static func label(_ tab: ChatListTab) -> String {
        switch tab {
        case .all: shellString("chatTabAll", "All")
        case .direct: shellString("chatTabDirect", "Direct")
        case .groups: shellString("chatTabGroups", "Groups")
        case .bots: shellString("chatTabBots", "Bots")
        }
    }
}

/// A filter chip of the chat's tab rows: tinted when selected, with an unread badge after the label.
/// Ported from: lib/features/chat/presentation/widgets/chat_tab_chip.dart
struct ChatTabChip: View {
    @Environment(\.appTheme) private var theme
    let label: String
    let selected: Bool
    var unread = 0
    let onTap: () -> Void

    var body: some View {
        HoverSurface(onTap: onTap, selected: selected, height: theme.sizes.control32 - theme.spacing.s4,
                     fill: selected ? theme.colors.sel : nil) {
            HStack(spacing: theme.spacing.s6) {
                Text(label).font(selected ? theme.typography.label : theme.typography.metaStrong)
                    .foregroundStyle(selected ? theme.colors.accent : theme.colors.tx2)
                AppCountBadge(unread)
            }
            .padding(.horizontal, theme.spacing.s12)
        }
        .fixedSize()
    }
}
