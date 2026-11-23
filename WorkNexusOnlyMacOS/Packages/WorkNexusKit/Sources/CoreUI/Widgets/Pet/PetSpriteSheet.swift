import AppKit
import CoreGraphics
import ImageIO

/// A pet's sprite sheet in the Codex pet format, cut into frames once: `PetAnimation.row` picks the row, the frame the cell.
/// Not in the Flutter app.
///
/// Two versions share the 8-column grid of 192 x 208 cells:
/// - v1 (1536 x 1872): the 9 animation rows - the bundled TBChat character, and older pets.
/// - v2 (1536 x 2288): the same 9 rows, a "looking straight at you" cell at row 0 column 6, and two more rows (9 and 10)
///   with 16 directions the pet can look in, clockwise from up (`lookUnitRect`).
public struct PetSpriteSheet: @unchecked Sendable {
    public static let cellWidth = 192, cellHeight = 208
    public static let columns = 8, rows = 9
    /// The rows of a v2 sheet; the look directions take its last two.
    public static let rowsV2 = 11
    /// How many directions a v2 sheet can look in.
    public static let lookDirections = 16

    public enum Version: Int, Sendable { case v1 = 1, v2 = 2 }

    private let frames: [PetAnimation: [CGImage]]
    /// The whole sheet: a layer shows one cell of it (`unitRect`) without cutting or scaling anything per frame.
    public let atlas: CGImage
    public let version: Version
    /// The pace its frames were drawn for.
    public let timing: PetTiming

    /// Nil when `atlas` is smaller than the 8 x 9 cells it should hold. A sheet tall enough for 11 rows is a v2 sheet.
    public init?(atlas: CGImage, timing: PetTiming = .steady) {
        guard atlas.width >= Self.columns * Self.cellWidth, atlas.height >= Self.rows * Self.cellHeight else { return nil }
        var cut: [PetAnimation: [CGImage]] = [:]
        for a in PetAnimation.allCases {
            cut[a] = (0..<a.frames).compactMap { col in
                atlas.cropping(to: CGRect(x: col * Self.cellWidth, y: a.row * Self.cellHeight, width: Self.cellWidth, height: Self.cellHeight))
            }
        }
        frames = cut
        self.atlas = atlas
        self.timing = timing
        version = atlas.height >= Self.rowsV2 * Self.cellHeight ? .v2 : .v1
    }

    /// A sheet on disk (PNG or WebP), drawn for the Codex timings unless told otherwise; nil when it cannot be read or is too small.
    public init?(contentsOf url: URL, timing: PetTiming = .codex) {
        // Decoded here and now (callers read installed pets off the main thread): left to the first draw, the whole sheet
        // was decoded on the main thread, a late frame every time a pet was chosen.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        self.init(atlas: image, timing: timing)
    }

    /// Whether the pet can look toward a point (a v2 sheet).
    public var canLook: Bool { version == .v2 }

    /// The cell of `animation`'s frame `index` in the atlas, in unit coordinates (what `CALayer.contentsRect` takes).
    public func unitRect(_ animation: PetAnimation, _ index: Int) -> CGRect {
        let count = max(animation.frames, 1)
        return unitRect(row: animation.row, column: ((index % count) + count) % count)
    }

    /// The cell of look direction `direction` (0 = up, clockwise, wrapping); nil on a v1 sheet.
    public func lookUnitRect(_ direction: Int) -> CGRect? {
        guard canLook else { return nil }
        let n = Self.lookDirections, d = ((direction % n) + n) % n
        return unitRect(row: Self.rows + d / Self.columns, column: d % Self.columns)
    }

    /// The cell where a v2 pet looks straight out; nil on a v1 sheet. Optional in the format: many pets leave it empty,
    /// so nothing shows it unless it is known to be drawn.
    public var neutralLookUnitRect: CGRect? { canLook ? unitRect(row: 0, column: 6) : nil }

    public func frame(_ animation: PetAnimation, _ index: Int) -> CGImage? {
        guard let all = frames[animation], !all.isEmpty else { return nil }
        return all[((index % all.count) + all.count) % all.count]
    }

    private func unitRect(row: Int, column: Int) -> CGRect {
        let w = CGFloat(atlas.width), h = CGFloat(atlas.height)
        return CGRect(x: CGFloat(column * Self.cellWidth) / w, y: CGFloat(row * Self.cellHeight) / h,
                      width: CGFloat(Self.cellWidth) / w, height: CGFloat(Self.cellHeight) / h)
    }

    /// Which of the 16 directions points from the pet toward something `dx` to the right and `dy` below it (screen
    /// coordinates, y down): 0 is straight up, counting clockwise.
    public static func lookDirection(dx: Double, dy: Double) -> Int {
        let degrees = atan2(dx, -dy) * 180 / .pi
        let step = 360.0 / Double(lookDirections)
        let n = lookDirections
        return ((Int((degrees / step).rounded()) % n) + n) % n
    }

    /// The sheet shipped with the app (`Pet/tbchat-pet.png` in the bundle); nil when it is not there.
    public static func bundled(bundle: Bundle = .main) -> PetSpriteSheet? {
        guard let url = bundle.url(forResource: "tbchat-pet", withExtension: "png", subdirectory: "Pet") ?? bundle.url(forResource: "tbchat-pet", withExtension: "png")
        else { return nil }
        return PetSpriteSheet(contentsOf: url, timing: .steady)
    }
}
