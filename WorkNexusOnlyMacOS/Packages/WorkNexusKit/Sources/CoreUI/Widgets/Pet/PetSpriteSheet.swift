import AppKit
import CoreGraphics
import ImageIO

/// The TBChat character's sprite sheet, cut into frames once: `PetAnimation.row` picks the row, the frame the cell.
public struct PetSpriteSheet: @unchecked Sendable {
    public static let cellWidth = 192, cellHeight = 208
    public static let columns = 8, rows = 9

    private let frames: [PetAnimation: [CGImage]]
    /// The whole sheet: a layer shows one cell of it (`unitRect`) without cutting or scaling anything per frame.
    public let atlas: CGImage

    /// Nil when `atlas` is smaller than the 8 x 9 cells it should hold.
    public init?(atlas: CGImage) {
        guard atlas.width >= Self.columns * Self.cellWidth, atlas.height >= Self.rows * Self.cellHeight else { return nil }
        var cut: [PetAnimation: [CGImage]] = [:]
        for a in PetAnimation.allCases {
            cut[a] = (0..<a.frames).compactMap { col in
                atlas.cropping(to: CGRect(x: col * Self.cellWidth, y: a.row * Self.cellHeight, width: Self.cellWidth, height: Self.cellHeight))
            }
        }
        frames = cut
        self.atlas = atlas
    }

    /// The cell of `animation`'s frame `index` in the atlas, in unit coordinates (what `CALayer.contentsRect` takes).
    public func unitRect(_ animation: PetAnimation, _ index: Int) -> CGRect {
        let count = max(animation.frames, 1), col = ((index % count) + count) % count
        let w = CGFloat(atlas.width), h = CGFloat(atlas.height)
        return CGRect(x: CGFloat(col * Self.cellWidth) / w, y: CGFloat(animation.row * Self.cellHeight) / h,
                      width: CGFloat(Self.cellWidth) / w, height: CGFloat(Self.cellHeight) / h)
    }

    public func frame(_ animation: PetAnimation, _ index: Int) -> CGImage? {
        guard let all = frames[animation], !all.isEmpty else { return nil }
        return all[((index % all.count) + all.count) % all.count]
    }

    /// The sheet shipped with the app (`Pet/tbchat-pet.png` in the bundle); nil when it is not there.
    public static func bundled(bundle: Bundle = .main) -> PetSpriteSheet? {
        guard let url = bundle.url(forResource: "tbchat-pet", withExtension: "png", subdirectory: "Pet") ?? bundle.url(forResource: "tbchat-pet", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return PetSpriteSheet(atlas: image)
    }
}
