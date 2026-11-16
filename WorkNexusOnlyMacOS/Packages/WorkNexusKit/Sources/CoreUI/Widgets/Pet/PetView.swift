import AppKit
import SwiftUI

/// The character standing in a room: draws the director's frame and moves it with the director's position. Only the
/// character itself takes the pointer (a click pokes it, a drag moves it), so what is under the rest of the room stays usable.
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
            Group {
                if let image = sheet.frame(director.animation, director.frame) {
                    Image(decorative: image, scale: 2).resizable().interpolation(.high).frame(width: width, height: height)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { director.poke() }
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("petRoom"))
                .onChanged { drag in
                    let start = dragStart ?? (director.x, director.y)
                    dragStart = start
                    director.place(x: start.x + Double(drag.translation.width / freeW), y: start.y + Double(drag.translation.height / freeH))
                }
                .onEnded { _ in dragStart = nil; onMoved?(director.x, director.y) })
            .offset(x: CGFloat(director.x) * freeW, y: CGFloat(director.y) * freeH)
            .help("TBChat")
        }
        .coordinateSpace(name: "petRoom")
        .task(id: reduceMotion) {
            director.reduceMotion = reduceMotion
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(director.frameDuration))
                director.tick()
            }
        }
    }
}
