/// Ported from: lib/features/chat/presentation/widgets/message_hover_actions.dart + message_context_menu.dart
import CoreUI
import SwiftUI

/// Zalo-style message actions: round buttons beside the bubble, level with its bottom edge, shown while the pointer is
/// over the message — the first actions (reply, open thread) and React as buttons, the rest under "…". They sit in the
/// bubble's row (outside the bubble, so they are clickable), keeping their space while hidden so nothing shifts on hover.
/// A right-click opens the whole list as a menu (reply stands apart from the rest; destructive actions come last).
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
    @State private var hovering = false
    @State private var picking = false

    var body: some View {
        let actions = ctx.actions(for: message, settings: settings, inThread: inThread)
        let canReact = ctx.canReact(to: message)
        if actions.isEmpty && !canReact {
            content
        } else {
            let buttonCount = inThread ? 2 : 1
            let own = Array(actions.prefix(buttonCount)), rest = Array(actions.dropFirst(buttonCount))
            let buttons = HStack(spacing: theme.spacing.s6) {
                ForEach(own) { a in RoundActionButton(icon: a.icon, help: a.title, action: a.run) }
                if canReact { ReactButton(ctx: ctx, message: message, mine: mineReactions, picking: $picking) }
                if !rest.isEmpty { MoreActionsMenu(actions: rest) }
            }
            .padding(.horizontal, theme.spacing.s8)
            .opacity(hovering || picking ? 1 : 0)
            .allowsHitTesting(hovering || picking)
            HStack(alignment: .bottom, spacing: 0) {
                if alignEnd { buttons }
                content.contextMenu { MessageContextMenu(actions: actions, canReact: canReact, picking: $picking) }
                if !alignEnd { buttons }
            }
            .onHover { hovering = $0 }
        }
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

/// "…": the actions that have no button of their own, as a menu.
private struct MoreActionsMenu: View {
    @Environment(\.appTheme) private var theme
    let actions: [MessageAction]

    var body: some View {
        Menu {
            ForEach(actions) { MessageMenuItem(action: $0) }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.tx2)
                .frame(width: 28, height: 28).background(theme.colors.panel, in: Circle())
                .overlay(Circle().stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help(L.moreActions)
    }
}

/// The right-click menu: reply stands apart from the rest; destructive actions come last.
private struct MessageContextMenu: View {
    let actions: [MessageAction]
    let canReact: Bool
    @Binding var picking: Bool

    var body: some View {
        let firstDestructive = actions.firstIndex { $0.destructive }
        if canReact { Button { picking = true } label: { Label(L.react, systemImage: "face.smiling") } }
        ForEach(Array(actions.enumerated()), id: \.element.id) { i, a in
            if i == 1 || i == firstDestructive { Divider() }
            MessageMenuItem(action: a)
        }
    }
}

private struct MessageMenuItem: View {
    let action: MessageAction
    var body: some View {
        Button(role: action.destructive ? .destructive : nil, action: action.run) { Label(action.title, systemImage: action.icon) }
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
