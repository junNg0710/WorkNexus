import AppKit
import SwiftUI

/// The character standing in a room. The sprite is one layer showing a cell of the sheet (`PetSpriteLayer`): a new frame
/// only moves the cell, nothing is cut or scaled again. While it walks its place is read from the director at the
/// display's rate (`TimelineView(.animation)`), so it glides; standing still nothing runs but the slow frame clock - and
/// that stops too while the window cannot be seen. Only the character itself takes the pointer (a click pokes it, a drag
/// moves it), so what is under the rest of the room stays usable. Not in the Flutter app.
public struct PetView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    let director: PetDirector
    let sheet: PetSpriteSheet
    /// How wide the character is drawn; its height keeps the sheet's cell proportions.
    var width: CGFloat = PetView.defaultWidth
    /// How wide the pet is drawn in the window.
    public static let defaultWidth: CGFloat = 84
    /// Whether a sheet that can look turns its head toward the pointer while it idles.
    var followsCursor = false
    /// Whether the frame clock stops while the app's window cannot be seen (not for a pet that floats on its own).
    var pausesWithApp = true
    /// Whether a drag moves it about its room (off when whatever holds it moves instead, like the floating pet's panel).
    var movable = true
    /// Whether it draws its speech bubble over itself (off when whatever holds it draws the bubble, like the floating pet's panel).
    var showsBubble = true
    var onTap: (() -> Void)?
    var onMoved: ((Double, Double) -> Void)?
    /// Opens what the pet is saying (a message, a notification: `PetDirector.link`) when it or its bubble is clicked.
    var onOpenLink: ((String) -> Void)?
    @Environment(\.petTripleTap) private var tripleTap
    @State private var taps = PetTapCounter()
    @State private var dragStart: (x: Double, y: Double)?
    @State private var gazeTracker = PetGazeTracker()
    @State private var hovering = false

    public init(director: PetDirector, sheet: PetSpriteSheet, width: CGFloat = PetView.defaultWidth, followsCursor: Bool = false,
                pausesWithApp: Bool = true, movable: Bool = true, showsBubble: Bool = true, onTap: (() -> Void)? = nil,
                onOpenLink: ((String) -> Void)? = nil, onMoved: ((Double, Double) -> Void)? = nil) {
        self.director = director; self.sheet = sheet; self.width = width; self.followsCursor = followsCursor
        self.pausesWithApp = pausesWithApp; self.movable = movable; self.showsBubble = showsBubble; self.onTap = onTap
        self.onOpenLink = onOpenLink; self.onMoved = onMoved
    }

    private var height: CGFloat { width * CGFloat(PetSpriteSheet.cellHeight) / CGFloat(PetSpriteSheet.cellWidth) }

    public var body: some View {
        GeometryReader { geo in
            let freeW = max(geo.size.width - width, 1), freeH = max(geo.size.height - height, 1)
            // Paused while it stands: the timeline then asks for no frames at all.
            TimelineView(.animation(paused: director.walk == nil)) { timeline in
                let left = CGFloat(director.x(at: timeline.date)) * freeW
                sprite(freeW: freeW, freeH: freeH, bubbleShift: Self.bubbleShift(petLeft: left, petWidth: width, roomWidth: geo.size.width))
                    .offset(x: left, y: CGFloat(director.y) * freeH)
            }
            // Only its own room: a pet that does not move about inside (the floating one) walks a strip its panel says.
            .onChange(of: geo.size.width, initial: true) { _, w in if movable { director.roomWidth = Double(max(w - width, 1)) } }
        }
        .coordinateSpace(name: "petRoom")
        .onChange(of: sheet.timing, initial: true) { _, t in director.timing = t }
        .task(id: TaskKey(reduceMotion: reduceMotion, follows: followsCursor && sheet.canLook, pauses: pausesWithApp)) {
            director.reduceMotion = reduceMotion
            let follows = followsCursor && sheet.canLook
            if !follows { director.gaze = nil }
            while !Task.isCancelled {
                // Nothing to animate for a window nobody can see (hidden to the tray, minimised, covered).
                guard !pausesWithApp || AppVisibility.isOnScreen else { try? await Task.sleep(for: .seconds(1)); continue }
                try? await Task.sleep(for: .seconds(director.frameDuration))
                if follows { director.gaze = gazeTracker.direction() }
                director.tick()
            }
        }
    }

    private struct TaskKey: Equatable { var reduceMotion, follows, pauses: Bool }

    private var cell: CGRect {
        if director.showsGaze, let g = director.gaze, let rect = sheet.lookUnitRect(g) { return rect }
        return sheet.unitRect(director.animation, director.frame)
    }

    /// How far the bubble moves sideways from above the pet's middle to stay inside the room (the tail moves back the
    /// other way, so it still points at the pet).
    static func bubbleShift(petLeft: CGFloat, petWidth: CGFloat, roomWidth: CGFloat) -> CGFloat {
        let w = PetSpeechBubble.maxWidth
        let centred = petLeft + petWidth / 2 - w / 2
        let clamped = min(max(centred, 0), max(roomWidth - w, 0))
        return clamped - centred
    }

    private func sprite(freeW: CGFloat, freeH: CGFloat, bubbleShift: CGFloat) -> some View {
        PetSpriteLayer(atlas: sheet.atlas, cell: cell, tracker: gazeTracker)
            .frame(width: width, height: height)
            .opacity(director.mood == .offline ? 0.55 : 1)
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel(director.status ?? "")
            .onHover { hovering = $0 }
            .overlay(alignment: .bottom) {
                // Above its head, as wide as a bubble gets; it never takes the pointer from what is under it.
                if showsBubble, let text = director.bubble(hovering: hovering) {
                    // The bubble keeps to the room (towards its middle when moved); the tail stays right above the pet.
                    VStack(spacing: -theme.borders.hairline) {
                        PetSpeechBubble(text, showsTail: false)
                            .frame(width: PetSpeechBubble.maxWidth,
                                   alignment: bubbleShift < 0 ? .trailing : (bubbleShift > 0 ? .leading : .center))
                            .offset(x: bubbleShift)
                        PetBubbleTail()
                    }
                    .offset(y: -height)
                        // Only a line that opens something takes the click (the tap below); any other lets it through.
                        .allowsHitTesting(director.link != nil)
                        .pointerStyle(director.link != nil ? .link : nil)
                        // Not an accessibility element: one appearing makes SwiftUI walk the window for focus whenever an
                        // accessibility client runs. What it says is the sprite's label instead.
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: director.bubble(hovering: hovering))
            .onTapGesture { taps.tap(armed: tripleTap?.armed() == true, single: tapped, triple: { tripleTap?.run() }) }
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("petRoom"))
                .onChanged { drag in
                    let start = dragStart ?? (director.x(at: Date()), director.y)
                    dragStart = start
                    director.place(x: start.x + Double(drag.translation.width / freeW), y: start.y + Double(drag.translation.height / freeH))
                }
                .onEnded { _ in dragStart = nil; onMoved?(director.x, director.y) }, isEnabled: movable)
    }

    /// One click on the pet: opens what it is saying, else pokes it (and whatever the holder does on a click).
    private func tapped() {
        if let link = director.link, let onOpenLink { director.hush(); onOpenLink(link) } else { director.poke(); onTap?() }
    }
}

/// One cell of the sprite sheet on a layer. Changing the frame changes `contentsRect` only (no implicit animation between cells).
struct PetSpriteLayer: NSViewRepresentable {
    let atlas: CGImage
    let cell: CGRect
    var tracker: PetGazeTracker?

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.contentsGravity = .resize
        v.layer?.minificationFilter = .trilinear
        v.layer?.magnificationFilter = .linear
        tracker?.view = v
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        let rect = Self.layerRect(cell)
        let sameAtlas = (v.layer?.contents as AnyObject?) === atlas
        guard !sameAtlas || v.layer?.contentsRect != rect else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !sameAtlas { v.layer?.contents = atlas }   // another pet chosen
        v.layer?.contentsRect = rect
        CATransaction.commit()
        tracker?.view = v
    }

    /// The atlas' rows count from the top; a layer's unit space from the bottom.
    static func layerRect(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height) }
}

/// Which way the pointer is from the sprite on screen, read once per frame (no event monitor, so nothing runs between frames).
@MainActor
final class PetGazeTracker {
    weak var view: NSView?
    /// Beyond this distance (points) the pet stops paying attention; within `tooClose` the pointer is on the pet itself.
    static let reach = 700.0, tooClose = 24.0

    func direction(pointer: NSPoint = NSEvent.mouseLocation) -> Int? {
        guard let view, let window = view.window, window.isVisible else { return nil }
        let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
        return Self.direction(from: NSPoint(x: frame.midX, y: frame.midY), to: pointer)
    }

    /// Screen coordinates count up from the bottom; the sheet's directions count clockwise from up.
    static func direction(from center: NSPoint, to pointer: NSPoint) -> Int? {
        let dx = Double(pointer.x - center.x), dy = Double(center.y - pointer.y)
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > tooClose, distance < reach else { return nil }
        return PetSpriteSheet.lookDirection(dx: dx, dy: dy)
    }

}
