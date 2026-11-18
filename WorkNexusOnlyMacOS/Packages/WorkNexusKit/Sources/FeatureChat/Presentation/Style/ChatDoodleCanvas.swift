/// Ported from: lib/features/chat/presentation/widgets/chat_wallpaper.dart (ChatWallpaper, _WallpaperPainter)
import SwiftUI

/// The doodle pattern background: a soft four-corner gradient under a tiled doodle pattern. The pattern's tile is drawn
/// once per look and kept, so a chat opening (every switch builds its pane anew) only paints the gradient and repeats
/// the tile — drawing the 64 doodles again each time held up the switch.
/// Equatable: its whole look is `palette` and `scale`, so a redraw of the chat around it (typing, a message arriving)
/// skips repainting the pattern.
public struct ChatDoodleCanvas: View, Equatable {
    @Environment(\.displayScale) private var displayScale
    let palette: ChatDoodlePalette
    let scale: CGFloat
    public init(palette: ChatDoodlePalette, scale: CGFloat = 1) { self.palette = palette; self.scale = scale }

    public nonisolated static func == (a: Self, b: Self) -> Bool { a.palette == b.palette && a.scale == b.scale }

    /// Doodles of the pattern: work and everyday things as SF Symbols (Flutter draws Lucide's light line icons).
    static let doodles = [
        "message", "cup.and.saucer", "paperplane", "lightbulb", "ladybug", "music.note", "heart", "star", "camera",
        "headphones", "leaf", "birthday.cake", "airplane", "chevron.left.forwardslash.chevron.right", "pin", "pawprint",
        "cloud", "face.smiling", "sailboat", "party.popper", "gamecontroller", "bicycle", "umbrella", "moon.stars", "book",
        "pencil", "gift", "balloon", "atom", "fork.knife", "envelope", "paintpalette", "guitars", "fish", "bell",
        "laptopcomputer", "flame", "hare", "tortoise", "sun.max", "snowflake", "bolt", "tree", "mug",
    ]

    /// Side of one pattern tile and how many doodles fit across it. Large and dense, so the repeat is hard to spot.
    static let tile: CGFloat = 448
    static let cells = 8

    public var body: some View {
        let pattern = Self.tileImage(ink: palette.ink, scale: scale, displayScale: displayScale)
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(Path(rect), with: .color(palette.base.color))
            // Each corner's colour fades out towards the others, which blends them like Telegram's four-point gradient.
            let anchors = [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)]
            for (i, corner) in palette.corners.enumerated() {
                let gradient = Gradient(colors: [corner.color, corner.opacity(0).color])
                ctx.fill(Path(rect), with: .radialGradient(gradient, center: anchors[i], startRadius: 0, endRadius: 1.3 * min(size.width, size.height)))
            }
            if let pattern { ctx.fill(Path(rect), with: .tiledImage(Image(decorative: pattern, scale: displayScale))) }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }

    private struct TileKey: Hashable { var ink: ChatColor; var scale: CGFloat; var displayScale: CGFloat }
    @MainActor private static var tiles: [TileKey: CGImage] = [:]

    /// One tile of doodles in `ink` on a clear ground, drawn at the screen's scale; made once per look.
    @MainActor static func tileImage(ink: ChatColor, scale: CGFloat, displayScale: CGFloat) -> CGImage? {
        let key = TileKey(ink: ink, scale: scale, displayScale: displayScale)
        if let kept = tiles[key] { return kept }
        let side = tile * scale
        let renderer = ImageRenderer(content: Canvas { ctx, _ in drawDoodles(&ctx, ink: ink.color, scale: scale) }.frame(width: side, height: side))
        renderer.scale = displayScale
        let image = renderer.cgImage
        tiles[key] = image
        return image
    }

    /// The doodles of one tile. Those near its right or bottom edge reach a little into the next tile: they are drawn
    /// again one tile up and to the left as well, so the repeated tile joins without cut-off doodles.
    private static func drawDoodles(_ ctx: inout GraphicsContext, ink: Color, scale: CGFloat) {
        let tile = Self.tile * scale, cell = tile / CGFloat(Self.cells)
        let marks = Self.marks(cell: cell)
        var resolved: [GraphicsContext.ResolvedImage] = []
        for m in marks {
            var r = ctx.resolve(Image(systemName: m.symbol))
            r.shading = .color(ink)
            resolved.append(r)
        }
        for offset in [CGPoint(x: 0, y: 0), CGPoint(x: -tile, y: 0), CGPoint(x: 0, y: -tile), CGPoint(x: -tile, y: -tile)] {
            for (i, m) in marks.enumerated() {
                var layer = ctx
                layer.translateBy(x: offset.x + m.at.x, y: offset.y + m.at.y)
                layer.rotate(by: .radians(m.angle))
                let box = CGRect(x: -m.size / 2, y: -m.size / 2, width: m.size, height: m.size)
                layer.draw(resolved[i], in: aspectFit(resolved[i].size, in: box))
            }
        }
    }

    private static func aspectFit(_ s: CGSize, in box: CGRect) -> CGRect {
        guard s.width > 0, s.height > 0 else { return box }
        let k = min(box.width / s.width, box.height / s.height)
        return CGRect(x: box.midX - s.width * k / 2, y: box.midY - s.height * k / 2, width: s.width * k, height: s.height * k)
    }

    struct Mark { var symbol: String; var at: CGPoint; var angle: Double; var size: CGFloat }

    /// The same arrangement in every tile; a fixed seed so it never shifts.
    static func marks(cell: CGFloat) -> [Mark] {
        var rng = SplitMix(seed: 7)
        var order = doodles
        // Each doodle before any repeats, so neighbours rarely match.
        for i in stride(from: order.count - 1, to: 0, by: -1) { order.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
        var out: [Mark] = []
        for row in 0..<cells {
            for col in 0..<cells {
                out.append(Mark(
                    symbol: order[(row * cells + col) % order.count],
                    at: CGPoint(x: (CGFloat(col) + 0.3 + rng.unit() * 0.4) * cell, y: (CGFloat(row) + 0.3 + rng.unit() * 0.4) * cell),
                    angle: (Double(rng.unit()) - 0.5) * 0.7, size: cell * (0.5 + rng.unit() * 0.1)))
            }
        }
        return out
    }
}

/// A tiny deterministic generator, so the pattern is the same on every launch.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// A value in 0..<1.
    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }
}
