/// Ported from: lib/features/chat/presentation/widgets/chat_typing_bubble.dart + typing_dots.dart + chat_typing_avatars.dart + chat_typing_label.dart
import CoreUI
import SwiftUI

/// A received-style bubble of rising dots under the newest message while anyone is typing, with who it is beside it.
/// Laid out like a received message's row so the bubble lines up with the messages above.
struct ChatTypingRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatStyle) private var style
    let ctx: ThreadContext
    let typing: [Int]
    let showSenders: Bool

    /// Who is typing, by name: one, two, or the first and a count of the rest.
    static func label(_ typing: [Int], name: (Int) -> String) -> String {
        switch typing.count {
        case 0: ""
        case 1: L.typingOne(name(typing[0]))
        case 2: L.typingTwo(name(typing[0]), name(typing[1]))
        default: L.typingMany(name(typing[0]), typing.count - 1)
        }
    }

    var body: some View {
        if let first = typing.first {
            let ink = style.ink(mine: false)
            let tailed = style.tail != nil
            let label = Self.label(typing) { ctx.name(of: $0) }
            HStack(alignment: .bottom, spacing: 0) {
                if showSenders || style.avatarInDirectChats {
                    ThreadAvatar(name: ctx.name(of: first), imageUrl: ctx.users[first]?.avatarUrl, shape: style.avatarShape, diameter: style.avatarSize)
                    Spacer().frame(width: theme.spacing.s8)
                }
                // Always the run's only bubble, so a tailed style draws its tail and the box makes its own room for it.
                MessageBubbleBox(
                    fill: style.bubbleFill(mine: false), hoverFill: ink.hoverFill, border: style.bubbleBorder(mine: false),
                    corners: style.corners(mine: false, firstOfRun: true, lastOfRun: true, withTail: tailed),
                    padding: style.padding, mine: false, tail: style.tail
                ) {
                    ThreadTypingDots(color: ink.meta.color, size: theme.spacing.s6).padding(.vertical, theme.spacing.s4).padding(.horizontal, theme.spacing.s2)
                }
                if typing.count > 1 {
                    Spacer().frame(width: theme.spacing.s8)
                    TypingOthers(ctx: ctx, ids: Array(typing.dropFirst()))
                }
                Spacer(minLength: 0)
            }
            .padding(.top, style.groupGap)
            .padding(.horizontal, theme.spacing.s24)
            .accessibilityElement(children: .ignore).accessibilityLabel(label).help(label)
            .transition(.opacity)
        }
    }
}

/// Everyone else typing, as small overlapping faces after the bubble, then "+N" for those beyond `maxFaces`.
private struct TypingOthers: View {
    @Environment(\.appTheme) private var theme
    let ctx: ThreadContext
    let ids: [Int]
    static let maxFaces = 3

    var body: some View {
        let face = theme.sizes.icon20, ring = theme.spacing.s2, step = face * 0.65
        let faces = Array(ids.prefix(Self.maxFaces)), rest = ids.count - faces.count
        HStack(spacing: theme.spacing.s4) {
            ZStack(alignment: .leading) {
                ForEach(Array(faces.enumerated()), id: \.offset) { i, id in
                    ThreadAvatar(name: ctx.name(of: id), imageUrl: ctx.users[id]?.avatarUrl, diameter: face)
                        .padding(ring).background(Circle().fill(theme.colors.panel))
                        .offset(x: step * CGFloat(i))
                }
            }
            .frame(width: step * CGFloat(max(0, faces.count - 1)) + face + ring * 2, height: face + ring * 2, alignment: .leading)
            if rest > 0 { Text("+\(rest)").font(theme.typography.caption).foregroundStyle(theme.colors.tx2) }
        }
    }
}

/// Three dots rising one after another, the familiar "someone is typing" cue. They hold still when the system asks for
/// reduced motion.
struct ThreadTypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    /// Diameter of one dot; gaps and the rise scale with it.
    let size: CGFloat

    static let period: TimeInterval = 1.2
    /// The share of the period each dot spends rising and falling, and how far behind its left neighbour it starts.
    static let riseShare = 0.4
    static let stagger = 0.15

    /// 0 at rest, 1 at the top of the rise, for dot `i` at wave position `t` (0...1).
    static func lift(_ i: Int, _ t: Double) -> Double {
        var phase = (t - Double(i) * stagger).truncatingRemainder(dividingBy: 1)
        if phase < 0 { phase += 1 }
        return phase < riseShare ? sin(Double.pi * phase / riseShare) : 0
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
            HStack(spacing: size * 0.5) {
                ForEach(0..<3, id: \.self) { i in
                    let lift = Self.lift(i, t)
                    Circle().fill(color).frame(width: size, height: size)
                        .offset(y: -size * 0.6 * lift).opacity(0.4 + 0.6 * lift)
                }
            }
            // Room above the dots for the rise, so it never overlaps the line above.
            .padding(.top, size * 0.6)
        }
    }
}
