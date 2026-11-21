/// Ported from: lib/features/chat/presentation/widgets/message_hover_actions.dart + message_context_menu.dart
import CoreUI
import SwiftUI

/// Zalo-style message actions: round buttons beside the bubble, level with its bottom edge, shown while the pointer is
/// over the message — the first actions (reply, open thread) and React as buttons, the rest under "…". They sit in the
/// bubble's row (outside the bubble, so they are clickable), keeping their space while hidden so nothing shifts on hover.
/// A right-click opens the whole list as a menu (reply stands apart from the rest; destructive actions come last); on the
/// text, a short one (copy the selection or the message, reply, forward, translate).
struct MessageHoverActions<Content: View>: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatSettings) private var settings
    let ctx: ThreadContext
    let message: ChatMessage
    /// Own messages (right side) get the buttons on their left.
    let alignEnd: Bool
    /// Reply, and "open thread" for a message in one, as own buttons.
    let inThread: Bool
    @ViewBuilder let content: Content
    @Environment(\.chatScrollActivity) private var scrolling
    @State private var hovering = false
    @State private var picking = false
    /// The "…" menu is open: the buttons stay while it is.
    @State private var menuOpen = false

    var body: some View {
        // While "Multiple select" is on a click picks the row: no buttons then.
        let live = (hovering || picking || menuOpen) && !ctx.state.isSelecting
        let buttons = HoverButtons(ctx: ctx, message: message, inThread: inThread, alignEnd: alignEnd, live: live,
                                   picking: $picking, menuOpen: $menuOpen)
        HStack(alignment: .bottom, spacing: 0) {
            if alignEnd { buttons }
            // The menu's rows are worked out when it opens, not for every row of the list on every redraw.
            content.contextMenu { MessageContextMenu(ctx: ctx, message: message, inThread: inThread, picking: $picking) }
                // On the text itself (or its translation) a right-click would open the text system's menu (Font, Spelling,
                // Services…): a short chat menu answers it instead, and the message's whole menu anywhere else on it. Only the row under the pointer carries the catcher (an AppKit view): one on
                // every row made the whole list heavier to lay out, hit-test and walk for focus.
                .background {
                    if hovering && !ctx.state.isSelecting {
                        MessageTextRightClick(active: true) { selection, onText in
                            onText ? ctx.textMenu(for: message, settings: settings, selection: selection)
                                   : ctx.messageMenu(for: message, settings: settings, inThread: inThread) { picking = true }
                        }
                    }
                }
            if !alignEnd { buttons }
        }
        // While the list scrolls, rows pass under a still pointer: lighting each up (and back) as it goes by redrew them for
        // nothing. A row lights up when the pointer moves onto it; leaving always counts.
        .onHover { inside in
            if inside, scrolling?.isScrolling == true { return }
            hovering = inside
        }
    }
}

/// The round buttons beside a bubble. Their actions are worked out only while they show (hovered, or a menu or picker of
/// theirs open); otherwise the row keeps their room empty, so nothing shifts when they appear. Building every row's
/// actions on every redraw made scrolling a long chat heavy.
private struct HoverButtons: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatSettings) private var settings
    let ctx: ThreadContext
    let message: ChatMessage
    let inThread: Bool
    let alignEnd: Bool
    let live: Bool
    @Binding var picking: Bool
    @Binding var menuOpen: Bool

    var body: some View {
        let ownCount = inThread ? 2 : 1
        let canReact = ctx.canReact(to: message)
        // Room for the most buttons it can have: its own, React, and "…".
        let slots = CGFloat(ownCount + (canReact ? 1 : 0) + 1)
        let width = slots * 28 + (slots - 1) * theme.spacing.s6 + theme.spacing.s8 * 2
        ZStack(alignment: alignEnd ? .trailing : .leading) {
            Color.clear
            if live {
                let actions = ctx.actions(for: message, settings: settings, inThread: inThread)
                let own = Array(actions.prefix(ownCount)), rest = Array(actions.dropFirst(ownCount))
                HStack(spacing: theme.spacing.s6) {
                    ForEach(own) { a in RoundActionButton(icon: a.icon, help: a.title, action: a.run) }
                    if canReact { ReactButton(ctx: ctx, message: message, mine: mineReactions, picking: $picking) }
                    if !rest.isEmpty { MoreActionsMenu(actions: rest, open: $menuOpen) }
                }
                .padding(.horizontal, theme.spacing.s8)
            }
        }
        .frame(width: width, height: 28)
    }

    private var mineReactions: Set<String> {
        guard let sid = message.serverId else { return [] }
        return Set((ctx.model.reactions[sid] ?? []).filter { $0.mine != nil }.map(\.emoji))
    }
}

/// "React": opens the emoji picker over its button.
private struct ReactButton: View {
    let ctx: ThreadContext
    let message: ChatMessage
    let mine: Set<String>
    @Binding var picking: Bool

    var body: some View {
        RoundActionButton(icon: "face.smiling", help: L.react) { picking = true }
            .popover(isPresented: $picking, arrowEdge: .top) {
                ReactionPickerPopover(selected: mine) { emoji in
                    picking = false
                    ctx.toggleReaction(message, emoji)
                }
            }
    }
}

/// "…": the actions that have no button of their own, as a native menu. A SwiftUI `Menu` here did not open: the buttons
/// show only while the pointer is over the message, and the menu taking the pointer hid them (and itself) again.
private struct MoreActionsMenu: View {
    let actions: [MessageAction]
    @Binding var open: Bool
    @State private var anchor = AppMenuAnchor()

    var body: some View {
        RoundActionButton(icon: "ellipsis", help: L.moreActions) {
            open = true
            AppNativeMenu.popUp(items(), under: anchor)
            open = false
        }
        .appMenu(anchor, help: L.moreActions, onOpenChange: { open = $0 }, items: items)
    }

    private func items() -> [AppNativeMenu.Item] {
        actions.map { a in a.nativeMenuItem(dividerBefore: a.sectionStart || a.destructive) }
    }
}

/// The right-click menu: reply stands apart from the rest; destructive actions come last.
private struct MessageContextMenu: View {
    @Environment(\.chatSettings) private var settings
    let ctx: ThreadContext
    let message: ChatMessage
    let inThread: Bool
    @Binding var picking: Bool

    var body: some View {
        let actions = ctx.actions(for: message, settings: settings, inThread: inThread)
        let canReact = ctx.canReact(to: message)
        let firstDestructive = actions.firstIndex { $0.destructive }
        if canReact { Button { picking = true } label: { Label(L.react, systemImage: "face.smiling") } }
        ForEach(Array(actions.enumerated()), id: \.element.id) { i, a in
            if i == 1 || i == firstDestructive || (a.sectionStart && i > 1) { Divider() }
            MessageMenuItem(action: a)
        }
    }
}

private struct MessageMenuItem: View {
    let action: MessageAction
    var body: some View {
        if action.children.isEmpty {
            Button(role: action.destructive ? .destructive : nil, action: action.run) { Label(action.title, systemImage: action.icon) }
        } else {
            Menu {
                ForEach(action.children) { MessageMenuItem(action: $0) }
            } label: { Label(action.title, systemImage: action.icon) }
        }
    }
}

/// A round button in the surface colour with a hairline border: it floats over the chat wallpaper, so it needs its own
/// opaque disc to stay legible.
struct RoundActionButton: View {
    @Environment(\.appTheme) private var theme
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.tx2)
                .frame(width: 28, height: 28).background(theme.colors.panel, in: Circle())
                .overlay(Circle().stroke(theme.colors.line, lineWidth: theme.borders.hairline))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).help(help).pointerStyle(.link)
    }
}
