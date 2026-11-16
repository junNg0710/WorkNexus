import AppKit
import SwiftUI

/// The character standing in a room. The sprite is one layer showing a cell of the sheet (`PetSpriteLayer`): a new frame
/// only moves the cell, nothing is cut or scaled again. While it walks its place is read from the director at the
/// display's rate (`TimelineView(.animation)`), so it glides; standing still nothing runs but the slow frame clock - and
/// that stops too while the window cannot be seen. Only the character itself takes the pointer (a click pokes it, a drag
/// moves it), so what is under the rest of the room stays usable.
public struct PetView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let director: PetDirector
    let sheet: PetSpriteSheet
    /// How wide the character is drawn; its height keeps the sheet's cell proportions.
    var width: CGFloat = 84
    var onMoved: ((Double, Double) -> Void)?
    @State private var dragStart: (x: Double, y: Double)?

    public init(director: PetDirector, sheet: PetSpriteSheet, width: CGFloat = 84, onMoved: ((Double, Double) -> Void)? = nil) {
        self.director = director; self.sheet = sheet; self.width = width; self.onMoved = onMoved
    }

    private var height: CGFloat { width * CGFloat(PetSpriteSheet.cellHeight) / CGFloat(PetSpriteSheet.cellWidth) }

    public var body: some View {
        GeometryReader { geo in
            let freeW = max(geo.size.width - width, 1), freeH = max(geo.size.height - height, 1)
            // Paused while it stands: the timeline then asks for no frames at all.
            TimelineView(.animation(paused: director.walk == nil)) { timeline in
                sprite(freeW: freeW, freeH: freeH)
                    .offset(x: CGFloat(director.x(at: timeline.date)) * freeW, y: CGFloat(director.y) * freeH)
            }
            .onChange(of: geo.size.width, initial: true) { _, w in director.roomWidth = Double(max(w - width, 1)) }
        }
        .coordinateSpace(name: "petRoom")
        .task(id: reduceMotion) {
            director.reduceMotion = reduceMotion
            while !Task.isCancelled {
                // Nothing to animate for a window nobody can see (hidden to the tray, minimised, covered).
                guard AppVisibility.isOnScreen else { try? await Task.sleep(for: .seconds(1)); continue }
                try? await Task.sleep(for: .seconds(director.frameDuration))
                director.tick()
            }
        }
    }

    private func sprite(freeW: CGFloat, freeH: CGFloat) -> some View {
        PetSpriteLayer(sheet: sheet, animation: director.animation, frame: director.frame)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture { director.poke() }
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("petRoom"))
                .onChanged { drag in
                    let start = dragStart ?? (director.x(at: Date()), director.y)
                    dragStart = start
                    director.place(x: start.x + Double(drag.translation.width / freeW), y: start.y + Double(drag.translation.height / freeH))
                }
                .onEnded { _ in dragStart = nil; onMoved?(director.x, director.y) })
            .help(appString("tipPet", "TBChat: click to wave, drag to move it. Turn it off in Settings"))
    }

}

/// One cell of the sprite sheet on a layer. Changing the frame changes `contentsRect` only (no implicit animation between cells).
struct PetSpriteLayer: NSViewRepresentable {
    let sheet: PetSpriteSheet
    let animation: PetAnimation
    let frame: Int

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.contents = sheet.atlas
        v.layer?.contentsGravity = .resize
        v.layer?.minificationFilter = .trilinear
        v.layer?.magnificationFilter = .linear
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        let rect = Self.layerRect(sheet.unitRect(animation, frame))
        guard v.layer?.contentsRect != rect else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        v.layer?.contentsRect = rect
        CATransaction.commit()
    }

    /// The atlas' rows count from the top; a layer's unit space from the bottom.
    static func layerRect(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height) }
}
