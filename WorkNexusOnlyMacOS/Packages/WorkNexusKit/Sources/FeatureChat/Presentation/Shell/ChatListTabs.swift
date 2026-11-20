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
            // All four tabs show whole: roomy when they fit, tighter when unread badges crowd the row (the last tab used to
            // be cut off there, with nothing saying the row scrolled). Scrolling is only for a list narrower still.
            ViewThatFits(in: .horizontal) {
                ChatTabRow(model: model, compact: false)
                ChatTabRow(model: model, compact: true)
                ScrollView(.horizontal, showsIndicators: false) { ChatTabRow(model: model, compact: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

/// The four tabs in a row; `compact` draws them closer together.
private struct ChatTabRow: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? theme.spacing.s2 : theme.spacing.s6) {
            ForEach(ChatListTab.allCases, id: \.self) { tab in
                ChatTabChip(label: ChatListTabs.label(tab), selected: tab == model.tab, unread: model.unread(tab), compact: compact) { model.tab = tab }
            }
        }
        .padding(.leading, theme.spacing.s12)
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
    /// Less room around the label, for a crowded row.
    var compact = false
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
            .padding(.horizontal, compact ? theme.spacing.s8 : theme.spacing.s12)
        }
        .fixedSize()
    }
}
