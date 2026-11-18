import CoreDomain
import CoreUI
import SwiftUI

/// A filter icon beside the chat list's tabs: opens the filter by status (all / unread) and by category tags. An icon rather
/// than a labelled dropdown, so it leaves the tabs their room; while it narrows the list it is tinted and carries a dot.
/// Ported from: lib/features/chat/presentation/widgets/chat_list_filter_button.dart
struct ChatListFilterButton: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    @State private var open = false

    var body: some View {
        let narrowed = model.listFilter.isNarrowed
        HoverSurface(onTap: { open.toggle() }, selected: narrowed || open, height: theme.sizes.control32 - theme.spacing.s6) {
            Image(systemName: "line.3.horizontal.decrease").font(.system(size: theme.sizes.icon14))
                .foregroundStyle(narrowed ? theme.colors.accent : theme.colors.tx2)
                .frame(width: theme.sizes.control32 - theme.spacing.s6)
        }
        .overlay(alignment: .topTrailing) {
            if narrowed {
                // An accent dot ringed in the pane's colour so it reads on the tinted button.
                Circle().fill(theme.colors.accent).frame(width: theme.spacing.s8, height: theme.spacing.s8)
                    .overlay { Circle().stroke(theme.colors.panel, lineWidth: theme.borders.thick) }
                    .allowsHitTesting(false)
            }
        }
        .help(shellString("chatCategorize", "Categorize"))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ChatListFilterPanel(model: model) { open = false; model.showCategoryManager = true }
                .frame(width: theme.sizes.toolPaneCompact)
        }
    }
}

/// The chat list's "Categorize" menu: by status (all chats or only unread ones, pick one) and by category tags (pick any;
/// none means all), then a way to manage the tags. Stays open while picking.
/// Ported from: lib/features/chat/presentation/widgets/chat_list_filter_panel.dart
struct ChatListFilterPanel: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let onManage: () -> Void

    var body: some View {
        let categories = model.categories
        let picked = model.listFilter.categories
        let unreadOnly = model.filter.unreadOnly
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Heading(text: shellString("chatFilterByStatus", "By status"))
                FilterRow(icon: unreadOnly ? "circle" : "largecircle.fill.circle", on: !unreadOnly,
                          label: shellString("chatFilterAll", "All")) { model.filter.unreadOnly = false }
                FilterRow(icon: unreadOnly ? "largecircle.fill.circle" : "circle", on: unreadOnly,
                          label: shellString("chatFilterUnread", "Unread")) { model.filter.unreadOnly = true }
                Divider().overlay(theme.colors.line).padding(.vertical, theme.spacing.s4)
                Heading(text: shellString("chatFilterByCategory", "By category tag"))
                if categories.isEmpty {
                    Text(shellString("chatNoCategories", "No tags yet. Right-click a chat and pick “Category…” to tag it."))
                        .font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, theme.spacing.s12).padding(.bottom, theme.spacing.s8)
                }
                ForEach(categories, id: \.name) { c in
                    FilterRow(icon: picked.contains(c.name) ? "checkmark.square.fill" : "square", on: picked.contains(c.name),
                              tag: chatNameHue(c.name, theme), label: c.name, unread: c.unread) { model.toggleCategoryFilter(c.name) }
                }
                Divider().overlay(theme.colors.line).padding(.vertical, theme.spacing.s4)
                FilterRow(icon: "gearshape", on: false, label: shellString("chatManageCategories", "Manage category tags"), action: onManage)
            }
            .padding(theme.spacing.s6)
        }
        .frame(maxHeight: theme.sizes.dialogLg)
    }
}

private struct Heading: View {
    @Environment(\.appTheme) private var theme
    let text: String

    var body: some View {
        Text(text).font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
            .padding(.horizontal, theme.spacing.s12).padding(.top, theme.spacing.s8).padding(.bottom, theme.spacing.s4)
    }
}

/// One pickable line: its control (radio, tick or icon), an optional coloured tag, the label and an optional unread count.
private struct FilterRow: View {
    @Environment(\.appTheme) private var theme
    let icon: String
    let on: Bool
    var tag: Color?
    let label: String
    var unread = 0
    let action: () -> Void

    var body: some View {
        HoverSurface(onTap: action) {
            HStack(spacing: theme.spacing.s10) {
                Image(systemName: icon).font(.system(size: theme.sizes.icon16))
                    .foregroundStyle(on ? theme.colors.accent : theme.colors.tx3).frame(width: theme.sizes.icon18)
                if let tag { Image(systemName: "tag.fill").font(.system(size: theme.sizes.icon14)).foregroundStyle(tag) }
                Text(label).font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if unread > 0 { UnreadBadge(count: unread) }
            }
            .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s8)
        }
    }
}
