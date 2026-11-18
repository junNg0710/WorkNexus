import AppKit
import SwiftUI

/// The pet's room over the window's content, in a SwiftUI hosting view of its own. Not in the Flutter app.
///
/// Why apart: in the window's own view graph every change of the pet - a new sprite frame several times a second, its
/// place at the display's rate while it walks, a speech bubble on hover - had SwiftUI update and lay out the whole
/// window (`NSHostingView.layout` → `ViewGraph.updateOutputs`), so a busy screen such as a chat stuttered whenever the
/// pet moved. Here the pet's updates stay inside this small graph. The view only takes the pointer over the pet itself:
/// anywhere else a click, a scroll or a hover goes to the content under it.
public struct PetStage<Content: View>: NSViewRepresentable {
    let content: Content
    /// Where the pet is, in the stage's coordinates (top-left origin), for the pointer; nil: nowhere.
    let petRect: @MainActor (CGSize) -> CGRect?

    public init(petRect: @escaping @MainActor (CGSize) -> CGRect?, @ViewBuilder content: () -> Content) {
        self.content = content(); self.petRect = petRect
    }

    public func makeNSView(context: Context) -> PetStageHostingView<Content> {
        let v = PetStageHostingView(rootView: content)
        v.sizingOptions = []          // its size never feeds back into the window's layout
        v.petRect = petRect
        return v
    }

    public func updateNSView(_ v: PetStageHostingView<Content>, context: Context) {
        v.rootView = content
        v.petRect = petRect
    }
}

/// A hosting view that is see-through for the pointer except over the pet.
public final class PetStageHostingView<Content: View>: NSHostingView<Content> {
    var petRect: (@MainActor (CGSize) -> CGRect?)?

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        // Hosting views are flipped (y down), like the rect.
        let flippedLocal = isFlipped ? local : NSPoint(x: local.x, y: bounds.height - local.y)
        guard Self.takesPointer(at: flippedLocal, petRect: petRect?(bounds.size)) else { return nil }
        return super.hitTest(point)
    }

    /// Only over the pet: everywhere else the pointer belongs to the content under the stage.
    static func takesPointer(at point: NSPoint, petRect: CGRect?) -> Bool { petRect?.contains(point) ?? false }

    /// The stage never becomes the first responder: typing stays in the content under it.
    public override var acceptsFirstResponder: Bool { false }
}

public extension PetView {
    /// Where the sprite is drawn in a room `room` big (top-left origin): the same sums as the view's own.
    static func spriteRect(director: PetDirector, room: CGSize, width: CGFloat, at date: Date = Date()) -> CGRect {
        let height = width * CGFloat(PetSpriteSheet.cellHeight) / CGFloat(PetSpriteSheet.cellWidth)
        let freeW = max(room.width - width, 1), freeH = max(room.height - height, 1)
        return CGRect(x: CGFloat(director.x(at: date)) * freeW, y: CGFloat(director.y) * freeH, width: width, height: height)
    }
}
