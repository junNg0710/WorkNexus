/// Ported from: lib/features/chat/presentation/widgets/bubble_tail.dart
import SwiftUI

/// The little pointer some messengers draw on a bubble.
public enum BubbleTailKind: Sendable, Hashable {
    /// Telegram: a curl leaving the bottom corner of the last bubble in a run.
    case curlBottom
    /// WeChat / TBChat: a small triangle near the top, pointing at the avatar.
    case triangleTop
}

/// The size of a bubble's tail.
public enum BubbleTail {
    /// Width the tail sticks out of the bubble (kept free beside it).
    public static let width: CGFloat = 7
    /// Height of the tail along the bubble's edge.
    public static let height: CGFloat = 14
    /// How far below the bubble's top a `triangleTop` starts.
    public static let topInset: CGFloat = 8
}

/// The four (circular) corner radii of a bubble, in absolute left/right terms.
public struct BubbleCorners: Hashable, Sendable {
    public var topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat
    public init(topLeft: CGFloat = 0, topRight: CGFloat = 0, bottomLeft: CGFloat = 0, bottomRight: CGFloat = 0) {
        self.topLeft = topLeft; self.topRight = topRight; self.bottomLeft = bottomLeft; self.bottomRight = bottomRight
    }
    public init(all r: CGFloat) { self.init(topLeft: r, topRight: r, bottomLeft: r, bottomRight: r) }

    /// The corners seen in a mirror (left and right swapped).
    var mirrored: BubbleCorners {
        BubbleCorners(topLeft: topRight, topRight: topLeft, bottomLeft: bottomRight, bottomRight: bottomLeft)
    }
}

/// A bubble and its tail as one shape: one fill and one outline around both, so a bordered bubble (TBChat's hairline)
/// has no seam where the tail meets it and the tail is outlined too. The tail sticks `BubbleTail.width` out of the box
/// on the avatar side (`tailOnLeft` for incoming messages); the caller keeps that room free.
public struct BubbleShape: Shape {
    public var kind: BubbleTailKind
    public var corners: BubbleCorners
    public var tailOnLeft: Bool
    /// How far below the top a `triangleTop` points — the avatar's centre, so it points at it. Defaults to just under
    /// the corner.
    public var tipOffset: CGFloat?

    public init(kind: BubbleTailKind, corners: BubbleCorners, tailOnLeft: Bool, tipOffset: CGFloat? = nil) {
        self.kind = kind; self.corners = corners; self.tailOnLeft = tailOnLeft; self.tipOffset = tipOffset
    }

    public func path(in rect: CGRect) -> Path { Self.outline(in: rect, kind: kind, corners: corners, tailOnLeft: tailOnLeft, tipOffset: tipOffset) }

    /// Kappa for a quarter circle drawn as one cubic Bezier.
    private static let k: CGFloat = 0.5522847498307936

    /// Distance below the box's top where the triangle's upper base starts (the apex sits `height * 0.35` lower).
    public static func triangleTop(rect: CGRect, corners: BubbleCorners, tailOnLeft: Bool, tipOffset: CGFloat?) -> CGFloat {
        let r = tailOnLeft ? corners : corners.mirrored
        let h = BubbleTail.height
        let tip = tipOffset ?? (BubbleTail.topInset + h * 0.5)
        // Clear of both corners' arcs, or the outline would double back over one and kink.
        let lowest = rect.height - r.bottomLeft - h * 0.7
        let upper = max(r.topLeft, lowest)
        return min(max(tip - h * 0.35, r.topLeft), upper)
    }

    /// The vertical position (in `rect`'s space) of the triangle's apex.
    public static func triangleApexY(rect: CGRect, corners: BubbleCorners, tailOnLeft: Bool, tipOffset: CGFloat?) -> CGFloat {
        rect.minY + triangleTop(rect: rect, corners: corners, tailOnLeft: tailOnLeft, tipOffset: tipOffset) + BubbleTail.height * 0.35
    }

    /// Drawn with the tail on the left; mirrored for a tail on the right.
    public static func outline(in rect: CGRect, kind: BubbleTailKind, corners: BubbleCorners, tailOnLeft: Bool, tipOffset: CGFloat?) -> Path {
        let r = tailOnLeft ? corners : corners.mirrored
        let l = rect.minX, t = rect.minY, rt = rect.maxX, b = rect.maxY
        let w = BubbleTail.width, h = BubbleTail.height
        var p = Path()
        p.move(to: CGPoint(x: l + r.topLeft, y: t))
        p.addLine(to: CGPoint(x: rt - r.topRight, y: t))
        corner(&p, from: CGPoint(x: rt - r.topRight, y: t), to: CGPoint(x: rt, y: t + r.topRight),
               c1: CGPoint(x: rt - r.topRight + k * r.topRight, y: t), c2: CGPoint(x: rt, y: t + r.topRight - k * r.topRight))
        p.addLine(to: CGPoint(x: rt, y: b - r.bottomRight))
        corner(&p, from: CGPoint(x: rt, y: b - r.bottomRight), to: CGPoint(x: rt - r.bottomRight, y: b),
               c1: CGPoint(x: rt, y: b - r.bottomRight + k * r.bottomRight), c2: CGPoint(x: rt - r.bottomRight + k * r.bottomRight, y: b))
        switch kind {
        case .curlBottom:
            // The bottom corner on the tail side is square: the curl takes it.
            p.addLine(to: CGPoint(x: l - w, y: b))
            p.addQuadCurve(to: CGPoint(x: l, y: b - h), control: CGPoint(x: l, y: b - h * 0.2))
        case .triangleTop:
            let top = triangleTop(rect: rect, corners: corners, tailOnLeft: tailOnLeft, tipOffset: tipOffset)
            p.addLine(to: CGPoint(x: l + r.bottomLeft, y: b))
            corner(&p, from: CGPoint(x: l + r.bottomLeft, y: b), to: CGPoint(x: l, y: b - r.bottomLeft),
                   c1: CGPoint(x: l + r.bottomLeft - k * r.bottomLeft, y: b), c2: CGPoint(x: l, y: b - r.bottomLeft + k * r.bottomLeft))
            p.addLine(to: CGPoint(x: l, y: t + top + h * 0.7))
            p.addLine(to: CGPoint(x: l - w, y: t + top + h * 0.35))
            p.addLine(to: CGPoint(x: l, y: t + top))
        }
        p.addLine(to: CGPoint(x: l, y: t + r.topLeft))
        corner(&p, from: CGPoint(x: l, y: t + r.topLeft), to: CGPoint(x: l + r.topLeft, y: t),
               c1: CGPoint(x: l, y: t + r.topLeft - k * r.topLeft), c2: CGPoint(x: l + r.topLeft - k * r.topLeft, y: t))
        p.closeSubpath()
        if tailOnLeft { return p }
        // Mirror around the box's vertical centre line: x' = (left + right) - x.
        return p.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0))
    }

    /// A quarter-circle corner as one cubic curve (a zero radius degenerates to the point itself).
    private static func corner(_ p: inout Path, from: CGPoint, to: CGPoint, c1: CGPoint, c2: CGPoint) {
        if from == to { return }
        p.addCurve(to: to, control1: c1, control2: c2)
    }
}
