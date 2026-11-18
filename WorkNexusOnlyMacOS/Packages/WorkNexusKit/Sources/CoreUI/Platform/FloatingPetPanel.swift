import AppKit
import Observation
import SwiftUI

/// The pet floating on the desktop: a small borderless, see-through panel above other apps' windows, on every Space and
/// beside full-screen apps, that never takes the keyboard or brings the app forward by itself. Where it was dragged to
/// is remembered (and brought back onto a screen if that screen is gone).
///
/// The panel is only as big as what it shows: it grows upward for a speech bubble and shrinks back after, so no empty
/// see-through area sits over other apps. The pet itself never moves when it does: its bottom centre (`anchor`) stays
/// put. Near a screen edge the grown panel is kept on the screen, and the pet is drawn `petShift` points off the panel's
/// middle so it stays where it stands. Not in the Flutter app.
@MainActor @Observable
public final class FloatingPetPanel {
    public static let shared = FloatingPetPanel()

    /// How far the pet stands from the middle of the panel (the panel was kept on the screen).
    public private(set) var petShift: CGFloat = 0

    @ObservationIgnored private var panel: PetPanel?
    @ObservationIgnored private var host: NSHostingView<AnyView>?
    @ObservationIgnored private var dragStart: (mouse: NSPoint, anchor: NSPoint)?
    @ObservationIgnored private var petSize = CGSize.zero
    @ObservationIgnored private var bubbleShown = false
    /// Where the pet stands on the desktop: its bottom centre.
    @ObservationIgnored private var anchor = NSPoint.zero
    @ObservationIgnored private let defaults: UserDefaults
    static let xKey = "pet.floating.centerX", yKey = "pet.floating.bottomY"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var isShown: Bool { panel?.isVisible == true }

    /// Shows `content` in the panel (or swaps it in when the panel is up), for a pet `petSize` points big.
    public func show(_ content: AnyView, petSize: CGSize) {
        self.petSize = petSize
        let panel = self.panel ?? makePanel()
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
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Makes room for a speech bubble above the pet, or gives it back.
    public func setBubble(_ shown: Bool) {
        guard shown != bubbleShown else { return }
        bubbleShown = shown
        layout()
    }

    static func size(pet: CGSize, bubble: Bool) -> CGSize {
        guard bubble else { return pet }
        return CGSize(width: max(pet.width, PetSpeechBubble.maxWidth + 12), height: pet.height + PetSpeechBubble.areaHeight)
    }

    /// The panel's frame for a pet standing at `anchor`: centred on it, kept inside `screen` sideways; and how far the pet
    /// then is from the frame's middle.
    static func frame(anchor: NSPoint, size: CGSize, screen: CGRect?) -> (frame: CGRect, petShift: CGFloat) {
        var x = anchor.x - size.width / 2
        if let screen, screen.width >= size.width { x = min(max(x, screen.minX), screen.maxX - size.width) }
        return (CGRect(x: x, y: anchor.y, width: size.width, height: size.height), anchor.x - (x + size.width / 2))
    }

    private func layout() {
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) }?.visibleFrame ?? NSScreen.main?.visibleFrame
        let placed = Self.frame(anchor: anchor, size: Self.size(pet: petSize, bubble: bubbleShown), screen: screen)
        if petShift != placed.petShift { petShift = placed.petShift }
        if panel.frame != placed.frame { panel.setFrame(placed.frame, display: true) }
    }

    public func hide() { panel?.orderOut(nil) }

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
        panel = p
        return p
    }
}

/// A panel that never becomes the key or main window (typing stays where it was).
final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
