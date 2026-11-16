/// Ported from: lib/core/widgets/celebration_overlay.dart + fireworks_painter.dart
import Observation
import SwiftUI

/// Counts celebrations; each `celebrate()` sets off one firework show over the whole window (see `CelebrationOverlay`).
/// The shell owns one (`ShellModel.celebration`) and hands views a `\.celebrate` action.
@MainActor @Observable
public final class CelebrationController {
    public private(set) var tick = 0
    public init() {}
    public func celebrate() { tick += 1 }
}

private struct CelebrateKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
public extension EnvironmentValues {
    /// Sets off the celebration (a bug or task resolved). A no-op outside `AppShell`.
    var celebrate: () -> Void {
        get { self[CelebrateKey.self] }
        set { self[CelebrateKey.self] = newValue }
    }
}

/// Draws a firework show over the window each time `controller.tick` changes. It never takes the pointer, and is skipped when
/// the system asks for reduced motion.
public struct CelebrationOverlay: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let controller: CelebrationController
    @State private var show: Show?

    struct Show: Equatable { var started: Date; var sparks: [FireworkSpark]; var id: Int }

    public init(controller: CelebrationController) { self.controller = controller }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                if let show {
                    TimelineView(.animation) { timeline in
                        let t = timeline.date.timeIntervalSince(show.started) / Fireworks.duration
                        Canvas { context, _ in
                            guard t >= 0, t < 1 else { return }
                            FireworksPainter(sparks: show.sparks, t: t, palette: palette, hot: theme.colors.onScrim).paint(&context)
                        }
                    }
                }
            }
            .onChange(of: controller.tick) { _, tick in start(tick, in: geo.size) }
        }
        .allowsHitTesting(false)
    }

    private var palette: [Color] { [theme.colors.accent, theme.colors.green, theme.colors.amber, theme.colors.red, theme.colors.violet] }

    private func start(_ tick: Int, in size: CGSize) {
        guard !reduceMotion else { return }
        show = Show(started: Date(), sparks: Fireworks.sparks(in: size, seed: UInt64(tick)), id: tick)
        Task {
            try? await Task.sleep(for: .seconds(Fireworks.duration + 0.1))
            if show?.id == tick { show = nil }
        }
    }
}

/// Paints a firework show at `t` (0-1). Each spark is a soft glow round a small core that starts `hot` (near white) and cools
/// to its palette colour, trailing a tail that tapers and fades back towards its burst.
struct FireworksPainter {
    let sparks: [FireworkSpark]
    let t: Double
    let palette: [Color]
    let hot: Color

    /// The tail's length (in show time) and how many pieces draw it: more pieces make a smoother taper.
    private static let tail = 0.035
    private static let tailPieces = 5

    func paint(_ context: inout GraphicsContext) {
        for spark in sparks {
            guard let now = Fireworks.frame(of: spark, at: t) else { continue }
            let colour = palette[spark.colour % palette.count]
            // Sparks twinkle out of step with each other as they fade.
            let twinkle = now.life < 0.4 ? 1.0 : 0.7 + 0.3 * sin(t * 90 + spark.angle * 13)
            let alpha = now.opacity * twinkle

            // Tail: pieces from the oldest (thin, faint) to the newest.
            var from = Fireworks.frame(of: spark, at: max(spark.start, t - Self.tail))
            for i in 1...Self.tailPieces {
                guard let start = from,
                      let to = Fireworks.frame(of: spark, at: max(spark.start, t - Self.tail * (1 - Double(i) / Double(Self.tailPieces)))) else { break }
                let k = Double(i) / Double(Self.tailPieces)
                var line = Path(); line.move(to: start.at); line.addLine(to: to.at)
                context.stroke(line, with: .color(colour.opacity(alpha * k * 0.7)),
                               style: StrokeStyle(lineWidth: 0.4 + 1.4 * k, lineCap: .round))
                from = to
            }

            // Head: a soft halo, then a small bright core cooling to its colour.
            context.fill(Path(ellipseIn: CGRect(x: now.at.x - 3.5, y: now.at.y - 3.5, width: 7, height: 7)),
                         with: .color(colour.opacity(alpha * 0.35)))
            let core = hot.mix(with: colour, by: min(1, now.life * 2.5))
            context.fill(Path(ellipseIn: CGRect(x: now.at.x - 1.6, y: now.at.y - 1.6, width: 3.2, height: 3.2)),
                         with: .color(core.opacity(alpha)))
        }
    }
}
