/// Ported from: lib/features/chat/presentation/widgets/message_bubble_box.dart
import SwiftUI

/// A message bubble's own shape: its fill, border, corners and tail. Under the pointer the fill (and its tail) takes
/// `hoverFill` over it, so only the bubble lights up, never the whole row.
struct MessageBubbleBox<Content: View>: View {
    let fill: ChatColor
    /// Tint laid over `fill` on hover (the bubble ink's `hoverFill`, so it reads on light and dark bubbles alike).
    let hoverFill: ChatColor
    var border: ChatColor?
    let corners: BubbleCorners
    let padding: EdgeInsets
    let mine: Bool
    /// Drawn on the avatar side when set; the box makes the room for it.
    var tail: BubbleTailKind?
    /// Where a top tail points, below the bubble's top (the avatar's centre).
    var tailTip: CGFloat?
    @ViewBuilder let content: Content
    @State private var hovered = false

    var body: some View {
        let color = (hovered ? hoverFill.over(fill) : fill).color
        let shape = outline
        content
            .padding(padding)
            .background(shape.fill(color))
            .overlay { if let border { shape.stroke(border.color, lineWidth: 1) } }
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
            // Room for the tail: the shape draws it outside the box, into this padding.
            .padding(.leading, tail != nil && !mine ? BubbleTail.width : 0)
            .padding(.trailing, tail != nil && mine ? BubbleTail.width : 0)
    }

    private var outline: AnyShape {
        if let tail {
            AnyShape(BubbleShape(kind: tail, corners: corners, tailOnLeft: !mine, tipOffset: tailTip))
        } else {
            AnyShape(UnevenRoundedRectangle(topLeadingRadius: corners.topLeft, bottomLeadingRadius: corners.bottomLeft,
                                            bottomTrailingRadius: corners.bottomRight, topTrailingRadius: corners.topRight))
        }
    }
}
