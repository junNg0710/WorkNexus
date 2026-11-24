/// Not in the Flutter app.
import SwiftUI

/// The stacks of a message row, each laying its children out in one pass.
///
/// `HStack` and `VStack` ask every child for its smallest and its largest size before they place anything, and again for
/// an alignment other than their default - so a bubble inside a bottom-aligned `HStack`, inside a trailing `VStack`,
/// inside the row's `HStack`, was built and measured several times over. Measured on 72 messages: the one `HStack` that
/// put the hover buttons beside a bubble doubled the cost of the bubble. These ask each child once, at the width the
/// stack itself is offered, and say nothing of alignment guides: children sit against the leading or the trailing edge.

/// Children one under the other with no gap, against the leading or the trailing edge; as wide as the widest.
struct ChatColumn: Layout {
    var trailing = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var width: CGFloat = 0, height: CGFloat = 0
        for child in subviews {
            let size = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
            width = max(width, size.width); height += size.height
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Each child at the very width it was measured with (the stack's own offer), so it is laid out as measured: a
        // text offered its own rounded width again could wrap one word sooner.
        let offer = ProposedViewSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? bounds.width, height: nil)
        var y = bounds.minY
        for child in subviews {
            let size = child.sizeThatFits(offer)
            child.place(at: CGPoint(x: trailing ? bounds.maxX - size.width : bounds.minX, y: y), anchor: .topLeading, proposal: offer)
            y += size.height
        }
    }
}

/// A message beside its sender's avatar: the avatar (the first child, when there is one) against the leading edge - the
/// trailing one for `alignEnd` - a gap, then the message, which gets the rest of the width and sits against the avatar.
/// As wide as it is offered, like the `HStack` with spacers it stands for.
struct ChatRowSides: Layout {
    var hasAvatar: Bool
    var alignEnd: Bool
    var gap: CGFloat
    /// The avatar and the message share their bottom edge (the avatar by the run's last bubble) instead of their top.
    var bottom: Bool

    private func parts(_ subviews: Subviews) -> (avatar: LayoutSubview?, content: LayoutSubview?) {
        hasAvatar && subviews.count > 1 ? (subviews[0], subviews[1]) : (nil, subviews.last)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let p = parts(subviews)
        let avatar = p.avatar?.sizeThatFits(.unspecified) ?? .zero
        let taken = p.avatar == nil ? 0 : avatar.width + gap
        let content = p.content?.sizeThatFits(ProposedViewSize(width: proposal.width.map { max(0, $0 - taken) }, height: nil)) ?? .zero
        let natural = taken + content.width
        return CGSize(width: proposal.width.map { $0.isFinite ? max($0, 0) : natural } ?? natural, height: max(avatar.height, content.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = parts(subviews)
        let avatar = p.avatar?.sizeThatFits(.unspecified) ?? .zero
        let taken = p.avatar == nil ? 0 : avatar.width + gap
        let offer = ProposedViewSize(width: max(0, bounds.width - taken), height: nil)
        let content = p.content?.sizeThatFits(offer) ?? .zero
        func y(_ height: CGFloat) -> CGFloat { bottom ? bounds.maxY - height : bounds.minY }
        p.avatar?.place(at: CGPoint(x: alignEnd ? bounds.maxX - avatar.width : bounds.minX, y: y(avatar.height)), anchor: .topLeading, proposal: .unspecified)
        p.content?.place(at: CGPoint(x: alignEnd ? bounds.maxX - taken - content.width : bounds.minX + taken, y: y(content.height)),
                         anchor: .topLeading, proposal: offer)
    }
}
