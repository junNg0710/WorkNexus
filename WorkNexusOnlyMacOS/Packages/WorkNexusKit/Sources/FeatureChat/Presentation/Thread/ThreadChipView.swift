/// Ported from: lib/features/chat/presentation/widgets/thread_chip.dart
import CoreUI
import SwiftUI

/// Under a thread's root message: who replied (overlapping avatars), how many replies and when the last one came. Opens
/// the thread.
struct ThreadChipView: View {
    @Environment(\.appTheme) private var theme
    let ctx: ThreadContext
    let summary: ThreadSummary
    let onTap: () -> Void

    static let maxFaces = 3

    var body: some View {
        let faces = Array(summary.replierIds.prefix(Self.maxFaces))
        let face = theme.spacing.s24, step = face * 0.62
        Button(action: onTap) {
            HStack(spacing: theme.spacing.s8) {
                ZStack(alignment: .leading) {
                    ForEach(Array(faces.enumerated()), id: \.offset) { i, id in
                        ThreadAvatar(name: ctx.name(of: id), imageUrl: ctx.users[id]?.avatarUrl, diameter: face)
                            // A ring in the chip colour separates the faces.
                            .overlay(Circle().stroke(theme.colors.panel, lineWidth: theme.borders.thick))
                            .offset(x: step * CGFloat(i))
                    }
                }
                .frame(width: face + step * CGFloat(max(0, faces.count - 1)), height: face, alignment: .leading)
                Text(L.replies(summary.count)).font(theme.typography.label).foregroundStyle(theme.colors.accent)
                Text(ChatTextLabels.listTime(summary.lastReplyAt)).font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
                Image(systemName: "chevron.right").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx3)
            }
            .padding(.leading, theme.spacing.s4).padding(.trailing, theme.spacing.s12).padding(.vertical, theme.spacing.s4)
            .background(theme.colors.panel, in: Capsule())
            .overlay(Capsule().stroke(theme.colors.line, lineWidth: theme.borders.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).pointerStyle(.link)
    }
}
