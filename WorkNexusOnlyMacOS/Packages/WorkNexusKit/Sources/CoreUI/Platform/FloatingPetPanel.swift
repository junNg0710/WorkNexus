import AppKit
import SwiftUI

/// The pet floating on the desktop: a small borderless, see-through panel above other apps' windows, on every Space and
/// beside full-screen apps, that never takes the keyboard or brings the app forward by itself. Where it was dragged to
/// is remembered (and brought back onto a screen if that screen is gone).
///
/// The pet's panel is always just as big as the pet and never changes size: a panel that grew and shrank for the speech
/// bubble drew its content one frame late in the new frame, so the pet jumped aside (and was cut in half) each time the
/// bubble came or went. The bubble has a panel of its own right above the pet's, always the same size, that the pointer
/// goes through. Near a screen edge the bubble's panel is kept on the screen and its tail is drawn `tailShift` points off
/// its middle, so it still points at the pet. Not in the Flutter app.
@MainActor
public final class FloatingPetPanel {
    public static let shared = FloatingPetPanel()

    private var panel: PetPanel?
    private var bubblePanel: PetPanel?
    private var host: NSHostingView<AnyView>?
    private var bubbleHost: NSHostingView<AnyView>?
    /// Draws the bubble for a line, with its tail that many points off its middle.
    private var makeBubble: ((String, CGFloat) -> AnyView)?
    private var bubbleText: String?
    private var dragStart: (mouse: NSPoint, anchor: NSPoint)?
    private var petSize = CGSize.zero
    /// Where the pet stands on the desktop: its bottom centre.
    private var anchor = NSPoint.zero
    private let defaults: UserDefaults
    static let xKey = "pet.floating.centerX", yKey = "pet.floating.bottomY"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var isShown: Bool { panel?.isVisible == true }

    /// Shows `content` in the panel (or swaps it in when the panel is up), for a pet `petSize` points big; `bubble` draws
    /// what it says above it.
    public func show(_ content: AnyView, petSize: CGSize, bubble: @escaping (String, CGFloat) -> AnyView) {
        self.petSize = petSize
        makeBubble = bubble
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let host { host.rootView = content } else {
            let h = NSHostingView(rootView: content)
            panel.contentView = h
            host = h
        }
        if !panel.isVisible {
            let saved = savedAnchor.map { NSPoint(x: $0.x - petSize.width / 2, y: $0.y) }
            let origin = Self.onScreen(origin: saved, size: petSize, screens: NSScreen.screens.map(\.visibleFrame))
            anchor = NSPoint(x: origin.x + petSize.width / 2, y: origin.y)
        }
        layout()
        if !panel.isVisible { panel.orderFrontRegardless(); layout() }
    }

    /// Shows what the pet says above it, or takes the bubble away (nil).
    public func setBubble(_ text: String?) {
        guard text != bubbleText else { return }
        bubbleText = text
        layout()
    }

    /// The bubble's panel: room for the widest bubble and its tail.
    static let bubbleSize = CGSize(width: PetSpeechBubble.maxWidth + 12, height: PetSpeechBubble.areaHeight)

    /// The bubble panel's frame above a pet whose head is at `anchor`: centred on it, kept inside `screen` sideways; and
    /// how far the pet then is from the frame's middle (where the tail goes).
    static func frame(anchor: NSPoint, size: CGSize, screen: CGRect?) -> (frame: CGRect, tailShift: CGFloat) {
        var x = anchor.x - size.width / 2
        if let screen, screen.width >= size.width { x = min(max(x, screen.minX), screen.maxX - size.width) }
        return (CGRect(x: x, y: anchor.y, width: size.width, height: size.height), anchor.x - (x + size.width / 2))
    }

    /// The pet's panel at the anchor; the bubble's panel above it while there is something to say.
    private func layout() {
        guard let panel else { return }
        let petFrame = CGRect(x: anchor.x - petSize.width / 2, y: anchor.y, width: petSize.width, height: petSize.height)
        if panel.frame != petFrame { panel.setFrame(petFrame, display: true) }
        guard let text = bubbleText, let makeBubble, panel.isVisible else { bubblePanel?.orderOut(nil); return }
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) }?.visibleFrame ?? NSScreen.main?.visibleFrame
        let placed = Self.frame(anchor: NSPoint(x: anchor.x, y: petFrame.maxY), size: Self.bubbleSize, screen: screen)
        let bubble = bubblePanel ?? makeBubblePanel()
        if let bubbleHost { bubbleHost.rootView = makeBubble(text, placed.tailShift) } else {
            let h = NSHostingView(rootView: makeBubble(text, placed.tailShift))
            bubble.contentView = h
            bubbleHost = h
        }
        if bubble.frame != placed.frame { bubble.setFrame(placed.frame, display: false) }
        bubbleHost?.layoutSubtreeIfNeeded()
        if !bubble.isVisible { bubble.orderFrontRegardless() }
    }

    public func hide() { panel?.orderOut(nil); bubblePanel?.orderOut(nil); bubbleText = nil }

    /// Follows a drag of the pet: the panel moves with the pointer; at the end its place is remembered.
    public func drag(ended: Bool) {
        guard panel != nil else { return }
        let mouse = NSEvent.mouseLocation
        let start = dragStart ?? (mouse, anchor)
        dragStart = start
        anchor = NSPoint(x: start.anchor.x + mouse.x - start.mouse.x, y: start.anchor.y + mouse.y - start.mouse.y)
        layout()
        if ended {
            dragStart = nil
            defaults.set(Double(anchor.x), forKey: Self.xKey); defaults.set(Double(anchor.y), forKey: Self.yKey)
        }
    }

    private var savedAnchor: NSPoint? {
        if defaults.object(forKey: Self.xKey) != nil {
            return NSPoint(x: defaults.double(forKey: Self.xKey), y: defaults.double(forKey: Self.yKey))
        }
        // 1.8.0 kept the panel's bottom-left corner, with the panel as wide as the pet.
        guard defaults.object(forKey: Self.legacyXKey) != nil else { return nil }
        return NSPoint(x: defaults.double(forKey: Self.legacyXKey) + petSize.width / 2, y: defaults.double(forKey: Self.legacyYKey))
    }
    static let legacyXKey = "pet.floating.x", legacyYKey = "pet.floating.y"

    /// `origin` when a panel of `size` there is mostly on one of `screens`; otherwise the bottom-right corner of the first.
    static func onScreen(origin: NSPoint?, size: CGSize, screens: [CGRect]) -> NSPoint {
        if let origin {
            let frame = CGRect(origin: origin, size: size)
            if screens.contains(where: { $0.intersection(frame).width >= size.width / 2 && $0.intersection(frame).height >= size.height / 2 }) {
                return origin
            }
        }
        guard let screen = screens.first else { return origin ?? .zero }
        let margin: CGFloat = 24
        return NSPoint(x: screen.maxX - size.width - margin, y: screen.minY + margin)
    }

    private func makeBubblePanel() -> PetPanel {
        let p = makePanel()
        p.ignoresMouseEvents = true          // what is under the bubble stays usable
        bubblePanel = p
        return p
    }

    private func makePanel() -> PetPanel {
        let p = PetPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.animationBehavior = .none
        return p
    }
}

/// A panel that never becomes the key or main window (typing stays where it was).
final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
