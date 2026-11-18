import AppKit
import SwiftUI

/// The pet floating on the desktop: a small borderless, see-through panel above other apps' windows, on every Space and
/// beside full-screen apps, that never takes the keyboard or brings the app forward by itself. Where it was dragged to
/// is remembered (and brought back onto a screen if that screen is gone). Not in the Flutter app.
@MainActor
public final class FloatingPetPanel {
    public static let shared = FloatingPetPanel()

    private var panel: PetPanel?
    private var host: NSHostingView<AnyView>?
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private let defaults: UserDefaults
    static let xKey = "pet.floating.x", yKey = "pet.floating.y"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var isShown: Bool { panel?.isVisible == true }

    /// Shows `content` in the panel (or swaps it in when the panel is up), `size` points big.
    public func show(_ content: AnyView, size: CGSize) {
        let panel = self.panel ?? makePanel()
        if let host { host.rootView = content } else {
            let h = NSHostingView(rootView: content)
            panel.contentView = h
            host = h
        }
        let wasShown = panel.isVisible
        panel.setContentSize(size)
        if !wasShown {
            panel.setFrameOrigin(Self.onScreen(origin: savedOrigin, size: size, screens: NSScreen.screens.map(\.visibleFrame)))
            panel.orderFrontRegardless()
        }
    }

    public func hide() { panel?.orderOut(nil) }

    /// Follows a drag of the pet: the panel moves with the pointer; at the end its place is remembered.
    public func drag(ended: Bool) {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let start = dragStart ?? (mouse, panel.frame.origin)
        dragStart = start
        panel.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
        if ended {
            dragStart = nil
            defaults.set(Double(panel.frame.origin.x), forKey: Self.xKey); defaults.set(Double(panel.frame.origin.y), forKey: Self.yKey)
        }
    }

    private var savedOrigin: NSPoint? {
        guard defaults.object(forKey: Self.xKey) != nil else { return nil }
        return NSPoint(x: defaults.double(forKey: Self.xKey), y: defaults.double(forKey: Self.yKey))
    }

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
