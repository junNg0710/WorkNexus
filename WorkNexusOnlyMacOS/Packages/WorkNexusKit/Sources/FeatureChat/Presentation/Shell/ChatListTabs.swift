import CoreDomain
import CoreUI
import SwiftUI

/// Above the chat list: filter chips — all, direct, groups, bots, each with the unread count of the chats it shows — and, on
/// the right, the filter by status and category tags.
/// Ported from: lib/features/chat/presentation/widgets/chat_list_tabs.dart
struct ChatListTabs: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing.s6) {
                    ForEach(ChatListTab.allCases, id: \.self) { tab in
                        ChatTabChip(label: Self.label(tab), selected: tab == model.tab, unread: model.unread(tab)) { model.tab = tab }
                    }
                }
                .padding(.leading, theme.spacing.s12)
            }
            // A hairline keeps the scrolled-under tabs from running into the filter.
            Rectangle().fill(theme.colors.line).frame(width: theme.borders.hairline, height: theme.sizes.icon16)
                .padding(.horizontal, theme.spacing.s6)
            ChatListFilterButton(model: model).padding(.trailing, theme.spacing.s12)
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
    /// An SF Symbol before the label (a category chip's folder).
    var icon: String?
    let onTap: () -> Void

    var body: some View {
        HoverSurface(onTap: onTap, selected: selected, height: theme.sizes.control32 - theme.spacing.s4,
                     fill: selected ? theme.colors.sel : nil) {
            HStack(spacing: theme.spacing.s6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: theme.sizes.icon14)).foregroundStyle(selected ? theme.colors.accent : theme.colors.tx2)
                }
                Text(label).font(selected ? theme.typography.label : theme.typography.metaStrong)
                    .foregroundStyle(selected ? theme.colors.accent : theme.colors.tx2)
                AppCountBadge(unread)
            }
            .padding(.horizontal, theme.spacing.s12)
        }
        .fixedSize()
    }
}
