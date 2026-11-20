/// Ported from: lib/features/chat/presentation/widgets/{chat_mention_list,chat_mention_overlay}.dart
import CoreUI
import SwiftUI

/// Suggestions while an `@name` is being typed: the chat's members (and "@all" in groups) matching it. Click or Enter/Tab inserts one.
struct ChatMentionList: View {
    @Environment(\.appTheme) private var theme
    let mentions: MentionAutocomplete
    let onPick: (MentionCandidate) -> Void

    var body: some View {
        if mentions.query != nil, !mentions.visible.isEmpty {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(mentions.visible.enumerated()), id: \.offset) { i, c in
                        MentionRow(candidate: c, highlighted: i == mentions.highlight, onHover: { mentions.highlightAt(i) }) { onPick(c) }
                    }
                }
                .padding(.vertical, theme.spacing.s4)
            }
            .frame(maxHeight: theme.sizes.control36 * 6)
            .fixedSize(horizontal: false, vertical: true)
            .background(theme.colors.card, in: RoundedRectangle(cornerRadius: theme.radii.lg))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
            .shadow(color: theme.colors.scrim.opacity(0.25), radius: 8, y: 2)
            .padding(.horizontal, theme.spacing.s12)
        }
    }
}

/// One suggestion: an avatar and the name; "@all" gets an accent @ disc and "Notify everyone · @All".
private struct MentionRow: View {
    @Environment(\.appTheme) private var theme
    let candidate: MentionCandidate
    let highlighted: Bool
    let onHover: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: theme.spacing.s12) {
                if candidate.userId == nil {
                    Image(systemName: "at").font(.system(size: theme.sizes.icon16, weight: .semibold)).foregroundStyle(theme.colors.accentTx)
                        .frame(width: theme.sizes.control32, height: theme.sizes.control32).background(theme.colors.accent, in: Circle())
                } else {
                    Text(initials).font(theme.typography.label).foregroundStyle(theme.colors.accentTx)
                        .frame(width: theme.sizes.control32, height: theme.sizes.control32).background(theme.colors.violet, in: Circle())
                }
                if candidate.userId == nil {
                    (Text(appString("chatMentionAll", "Notify everyone")) + Text("  ·  @All").foregroundStyle(theme.colors.accent))
                        .font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(1)
                } else {
                    Text(candidate.name).font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing.s16)
            .padding(.vertical, theme.spacing.s6)
            .background(highlighted ? theme.colors.sel : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { onHover() } }
    }

    private var initials: String { String(candidate.name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased() }
}
