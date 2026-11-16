/// Ported from: lib/features/chat/presentation/widgets/chat_avatar_crop_view.dart (the frame maths of `_ChatAvatarCropViewState`)
import CoreDomain
import CoreGraphics
import Foundation

/// The square frame over a picture shown at `scale`: it starts on the biggest centred square, moves inside the picture and
/// resizes from a corner (the opposite corner stays put). Pure maths, in view points; `crop` converts back to picture pixels.
struct AvatarCropGeometry: Equatable {
    /// Which corner a resize drags: -1 is left/top, 1 is right/bottom.
    struct Corner: Hashable { var x: CGFloat; var y: CGFloat }
    static let corners = [Corner(x: -1, y: -1), Corner(x: 1, y: -1), Corner(x: -1, y: 1), Corner(x: 1, y: 1)]

    /// Where a corner drag started and where the pointer would be, unclamped: it keeps following the pointer while the frame
    /// is stopped at an edge.
    struct Resize { var pointer: CGPoint; var anchor: CGPoint; var startSide: CGFloat }

    /// Picture px → view points.
    let scale: CGFloat
    let shown: CGSize
    let grip: CGFloat
    private(set) var frame: CGRect

    /// The whole picture fitted in `maxSize` (minus room for the corner grips, which straddle its edge).
    init(imageSize: CGSize, maxSize: CGSize, grip: CGFloat) {
        self.grip = grip
        scale = min((maxSize.width - grip) / imageSize.width, (maxSize.height - grip) / imageSize.height)
        shown = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let side = min(shown.width, shown.height)
        frame = CGRect(x: (shown.width - side) / 2, y: (shown.height - side) / 2, width: side, height: side)
    }

    mutating func move(by delta: CGSize) {
        let x = min(max(frame.minX + delta.width, 0), shown.width - frame.width)
        let y = min(max(frame.minY + delta.height, 0), shown.height - frame.height)
        frame = CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    func beginResize(_ corner: Corner) -> Resize {
        Resize(pointer: point(corner, in: frame), anchor: point(Corner(x: -corner.x, y: -corner.y), in: frame), startSide: frame.width)
    }

    /// Resizes from `corner`, the opposite corner staying put.
    mutating func resize(_ corner: Corner, by delta: CGSize, _ r: inout Resize) {
        r.pointer = CGPoint(x: r.pointer.x + delta.width, y: r.pointer.y + delta.height)
        let roomX = corner.x > 0 ? shown.width - r.anchor.x : r.anchor.x
        let roomY = corner.y > 0 ? shown.height - r.anchor.y : r.anchor.y
        let room = min(roomX, roomY)
        // The axis the pointer moved more along sets the side, so the corner follows it whichever way it is dragged.
        let grewX = (r.pointer.x - r.anchor.x) * corner.x - r.startSide
        let grewY = (r.pointer.y - r.anchor.y) * corner.y - r.startSide
        let wanted = r.startSide + (abs(grewX) > abs(grewY) ? grewX : grewY)
        let side = min(max(wanted, min(grip * 2, room)), room)
        frame = CGRect(x: corner.x > 0 ? r.anchor.x : r.anchor.x - side, y: corner.y > 0 ? r.anchor.y : r.anchor.y - side, width: side, height: side)
    }

    func point(_ corner: Corner, in rect: CGRect) -> CGPoint {
        CGPoint(x: corner.x > 0 ? rect.maxX : rect.minX, y: corner.y > 0 ? rect.maxY : rect.minY)
    }

    /// The frame in the picture's own pixels.
    var crop: ChatAvatarCrop { ChatAvatarCrop(left: frame.minX / scale, top: frame.minY / scale, side: frame.width / scale) }
}
