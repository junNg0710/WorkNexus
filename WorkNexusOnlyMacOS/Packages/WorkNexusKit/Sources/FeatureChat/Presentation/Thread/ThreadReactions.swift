/// Ported from: lib/features/chat/presentation/widgets/reaction_chips.dart + reaction_picker.dart + providers/reaction_controller.dart
import CoreDomain
import CoreUI
import SwiftUI

extension ThreadContext {
    /// Adds `emoji` as a reaction to `message`, or takes the user's own back when they already used it.
    func toggleReaction(_ message: ChatMessage, _ emoji: String) {
        let reactions = message.serverId.flatMap { model.reactions[$0] } ?? []
        let chat = services.chat, report = model.report
        Task { @MainActor in
            if case .failure(let f) = await ToggleReaction(chat)(message, emoji, reactions: reactions) { report(f.message) }
        }
    }

    /// Whether the hover actions offer a reaction to `message`: reactions are on, and it is stored, not retracted and not
    /// itself a reaction.
    func canReact(to message: ChatMessage) -> Bool {
        model.reactionsOn && message.serverId != nil && !message.deleted && !message.isReaction
    }
}

/// Under a message: what people reacted to it with, one chip per emoji with how many used it. The user's own are tinted;
/// tapping a chip adds the user's reaction with that emoji or takes it back.
struct ReactionChipsView: View {
    @Environment(\.appTheme) private var theme
    let ctx: ThreadContext
    let message: ChatMessage
    let alignEnd: Bool

    var body: some View {
        if let sid = message.serverId, let reactions = ctx.model.reactions[sid], !reactions.isEmpty {
            FlowLayout(spacing: theme.spacing.s4) {
                ForEach(reactions, id: \.emoji) { r in
                    ReactionChip(reaction: r, tooltip: L.reactionBy(r.userIds.map { ctx.name(of: $0) }.joined(separator: ", "), r.emoji)) {
                        ctx.toggleReaction(message, r.emoji)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: alignEnd ? .trailing : .leading)
            .padding(.top, theme.spacing.s4)
        }
    }
}

private struct ReactionChip: View {
    @Environment(\.appTheme) private var theme
    let reaction: MessageReaction
    let tooltip: String
    let onTap: () -> Void

    var body: some View {
        let mine = reaction.mine != nil
        Button(action: onTap) {
            HStack(spacing: theme.spacing.s4) {
                Text(reaction.emoji).font(theme.typography.body)
                if reaction.count > 1 {
                    Text("\(reaction.count)").font(theme.typography.label).foregroundStyle(mine ? theme.colors.accent : theme.colors.tx2)
                }
            }
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s4)
            .background(mine ? theme.colors.sel : theme.colors.panel, in: Capsule())
            .overlay(Capsule().stroke(mine ? theme.colors.selLine : theme.colors.line, lineWidth: theme.borders.hairline))
        }
        .buttonStyle(.plain).help(tooltip).pointerStyle(.link)
    }
}

/// The emoji offered for a quick reaction.
let kQuickReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

/// More emoji for the "+" of the picker.
private let kMoreReactions = [
    "😀", "😁", "😅", "🤣", "😊", "😍", "😘", "😎", "🤔", "😴", "😭", "😡", "👏", "🙌", "💪", "👀", "🎉", "🔥", "✅", "❌",
    "💯", "🚀", "👌", "🤝", "🙈", "🤯", "🥳", "😬", "😇", "🤗", "😉", "😋", "🤩", "😱", "🥲", "🫡", "💡", "⭐", "❓", "👎",
]

/// A row of quick reaction emoji over the "react" button, the ones in `selected` marked, ending in a button that swaps it
/// for more emoji. Picking one calls `onPick` and closes the popover.
struct ReactionPickerPopover: View {
    @Environment(\.appTheme) private var theme
    let selected: Set<String>
    let onPick: (String) -> Void
    @State private var all = false

    var body: some View {
        Group {
            if all {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(theme.spacing.s40 - 4), spacing: theme.spacing.s2), count: 8), spacing: theme.spacing.s2) {
                    ForEach(kMoreReactions, id: \.self) { EmojiPickButton(emoji: $0, selected: selected.contains($0), onPick: onPick) }
                }
            } else {
                HStack(spacing: theme.spacing.s2) {
                    ForEach(kQuickReactions, id: \.self) { EmojiPickButton(emoji: $0, selected: selected.contains($0), onPick: onPick) }
                    Button { all = true } label: { Image(systemName: "plus").frame(width: 32, height: 32) }
                        .buttonStyle(.plain).help(L.reactMore).foregroundStyle(theme.colors.tx2)
                }
            }
        }
        .padding(theme.spacing.s4)
    }
}

private struct EmojiPickButton: View {
    @Environment(\.appTheme) private var theme
    let emoji: String
    let selected: Bool
    let onPick: (String) -> Void

    var body: some View {
        Button { onPick(emoji) } label: {
            Text(emoji).font(theme.typography.titleSm).frame(width: 36, height: 36)
                .background(selected ? theme.colors.sel : .clear, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .overlay { if selected { RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.selLine) } }
        }
        .buttonStyle(.plain).pointerStyle(.link)
    }
}
