import SwiftUI

/// Ported from: lib/core/widgets/video/video_seek_bar.dart
/// A video's seek bar: track, what is loaded, what has played and a knob, drawn from the player's live position.
/// Hovering thickens it and shows the time under the pointer; a click or drag moves the knob at once and seeks when
/// let go, so a streamed video is not asked to seek on every pixel.
struct VideoSeekBar: View {
    @Environment(\.appTheme) private var theme
    let model: AppVideoPlayerModel
    @State private var hoverX: CGFloat?
    @State private var dragFraction: Double?

    private func fraction(_ x: CGFloat, _ width: CGFloat) -> Double { width <= 0 ? 0 : min(max(Double(x / width), 0), 1) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let active = hoverX != nil || dragFraction != nil
            TimelineView(.animation(paused: !model.isPlaying && dragFraction == nil)) { _ in
                let _ = model.positionVersion
                let total = model.duration
                let played = dragFraction ?? (total > 0 ? min(max(model.currentSeconds / total, 0), 1) : 0)
                let pointer = dragFraction.map { CGFloat($0) * width } ?? hoverX
                ZStack(alignment: .leading) {
                    SeekTrack(model: model, played: played, width: width, active: active)
                    if let pointer, total > 0 {
                        SeekTimeBubble(label: formatVideoTime(total * fraction(pointer, width)), x: pointer, width: width)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { dragFraction = fraction($0.location.x, width) }
                .onEnded { _ in
                    if let f = dragFraction { model.seek(to: model.duration * f) }
                    dragFraction = nil
                })
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hoverX = p.x
                case .ended: hoverX = nil
                }
            }
            .pointerStyle(.link)
        }
        .frame(height: theme.sizes.control32 - theme.spacing.s8)
    }
}

private struct SeekTrack: View {
    @Environment(\.appTheme) private var theme
    let model: AppVideoPlayerModel
    let played: Double
    let width: CGFloat
    let active: Bool

    var body: some View {
        let thickness = active ? theme.spacing.s6 : theme.spacing.s4
        let knob = active ? theme.spacing.s12 : theme.spacing.s8
        let total = max(model.duration, 0.001)
        ZStack(alignment: .leading) {
            Capsule().fill(theme.colors.tx.opacity(0.14)).frame(height: thickness)
            ForEach(Array(model.buffered.enumerated()), id: \.offset) { _, r in
                Capsule().fill(theme.colors.tx.opacity(0.32))
                    .frame(width: max(CGFloat((r.upperBound - r.lowerBound) / total) * width, 0), height: thickness)
                    .offset(x: CGFloat(r.lowerBound / total) * width)
            }
            Capsule().fill(theme.colors.accent).frame(width: max(CGFloat(played) * width, 0), height: thickness)
            Circle().fill(theme.colors.accent).frame(width: knob, height: knob)
                .offset(x: min(max(CGFloat(played) * width - knob / 2, 0), max(width - knob, 0)))
        }
        .animation(.easeOut(duration: theme.motion.fast), value: active)
    }
}

/// The time under the pointer, floating above the bar.
private struct SeekTimeBubble: View {
    @Environment(\.appTheme) private var theme
    let label: String
    let x: CGFloat
    let width: CGFloat
    @State private var bubbleWidth: CGFloat = 48

    var body: some View {
        Text(label).font(theme.typography.mono).foregroundStyle(theme.colors.onScrim)
            .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s2)
            .background(theme.colors.scrim.opacity(0.75), in: RoundedRectangle(cornerRadius: theme.radii.sm))
            .background(GeometryReader { g in Color.clear.onAppear { bubbleWidth = g.size.width }.onChange(of: label) { _, _ in bubbleWidth = g.size.width } })
            .offset(x: min(max(x - bubbleWidth / 2, 0), max(width - bubbleWidth, 0)), y: -(theme.sizes.control32 - theme.spacing.s4))
            .allowsHitTesting(false)
    }
}
