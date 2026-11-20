import AppKit
import QuartzCore
import SwiftUI

/// The pet floating on the desktop: a small borderless, see-through panel above other apps' windows, on every Space and
/// beside full-screen apps, that never takes the keyboard or brings the app forward by itself. Where it was dragged to
/// is remembered (and brought back onto a screen if that screen is gone).
///
/// The pet's panel is always just as big as the pet and never changes size: a panel that grew and shrank for the speech
/// bubble drew its content one frame late in the new frame, so the pet jumped aside (and was cut in half) each time the
/// bubble came or went. The bubble has a panel of its own right above the pet's, always the same size, that the pointer
/// goes through. Near a screen edge the bubble's panel is kept on the screen and its tail is drawn `tailShift` points off
/// its middle, so it still points at the pet.
///
/// Now and then the pet strolls: across the whole width of the app's window when it stands over it, else along a strip
/// around the place it was put (`strollSpan`); kept on its screen. Its director decides the walk, the panel follows it
/// at the display's rate (`follow`), from wherever the pet stands to the walk's end. A bubble that says something the
/// user can open (a message, a notification) takes the click; any other lets the pointer through. Not in the Flutter app.
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
    /// Where it was put (shown, or dragged to): the middle of the strip it strolls along.
    private var home = NSPoint.zero
    private var walk: PetDirector.Walk?
    /// Where the walk under way set off from and goes to (the pet's middle).
    private var walkFrom: CGFloat = 0, walkTo: CGFloat = 0
    private var ticker: DisplayTicker?
    /// What a click on the bubble does; nil: the bubble lets the pointer through.
    private var bubbleTap: (() -> Void)?
    /// What the bubble shows now, so it is drawn again only when that changes (not on every step of a walk).
    private var shownBubble: (text: String, tailShift: CGFloat, clickable: Bool)?
    private let defaults: UserDefaults
    static let xKey = "pet.floating.centerX", yKey = "pet.floating.bottomY"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // A screen plugged in or out, or its size or Dock changed: the pet may now stand off it, or under the Dock.
        screensObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepOnScreen() }
        }
    }

    private var screensObserver: NSObjectProtocol?

    /// Moves a shown pet back inside the usable part of the nearest screen (no walk under way), where it then strolls.
    private func keepOnScreen() {
        guard isShown, petSize != .zero else { return }
        let origin = NSPoint(x: anchor.x - petSize.width / 2, y: anchor.y)
        let inside = Self.onScreen(origin: origin, size: petSize, screens: NSScreen.screens.map(\.visibleFrame))
        guard inside != origin else { return }
        walk = nil; stopTicker()
        anchor = NSPoint(x: inside.x + petSize.width / 2, y: inside.y)
        home = anchor
        layout()
    }

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
            home = anchor
        }
        layout()
        if !panel.isVisible { panel.orderFrontRegardless(); layout() }
    }

    /// Shows what the pet says above it, or takes the bubble away (nil). With `onTap` a click on the bubble does it.
    public func setBubble(_ text: String?, onTap: (() -> Void)? = nil) {
        guard text != bubbleText || (onTap == nil) != (bubbleTap == nil) else { bubbleTap = onTap; return }
        bubbleText = text; bubbleTap = onTap
        layout()
    }

    /// How wide the strip is that the pet strolls along, around the place it was put.
    static let strollSpan: CGFloat = 360

    /// The strip a pet `petWidth` wide strolls along around `home` (kept inside `screen`): where its middle is at the left
    /// end, and how many points it can go from there.
    /// Over the app's `window` (sideways), the strip is the window's width instead.
    static func strip(home: CGFloat, petWidth: CGFloat, span: CGFloat, screen: CGRect?, window: CGRect? = nil) -> (start: CGFloat, travel: CGFloat) {
        if let window, window.minX <= home, home <= window.maxX {
            let left = max(window.minX, screen?.minX ?? window.minX), right = min(window.maxX, screen?.maxX ?? window.maxX)
            if right - left >= petWidth * 2 { return (left + petWidth / 2, right - left - petWidth) }
        }
        var minX = home - span / 2
        if let screen, screen.width >= span { minX = min(max(minX, screen.minX), screen.maxX - span) }
        return (minX + petWidth / 2, max(span - petWidth, 1))
    }

    private var currentStrip: (start: CGFloat, travel: CGFloat) {
        Self.strip(home: home.x, petWidth: petSize.width, span: Self.strollSpan, screen: Self.screen(at: home), window: Self.appWindowFrame())
    }

    /// The app's main window on screen (the biggest ordinary one), if it is up.
    static func appWindowFrame() -> CGRect? {
        NSApp?.windows.filter { $0.isVisible && !$0.isMiniaturized && !($0 is NSPanel) && $0.level == .normal && $0.frame.width >= 400 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.frame
    }

    /// Where along its strip the pet stands (0 at the left end, 1 at the right) and how long the strip is, in points: what
    /// its director needs to plan a walk.
    public var stroll: (x: Double, points: Double) {
        let s = currentStrip
        return (min(max(Double((anchor.x - s.start) / s.travel), 0), 1), Double(s.travel))
    }

    /// Moves the panel along with the pet's walk until it is over (nil: it stands, wherever it got to). The walk goes
    /// from where the pet stands now - the window may have moved since it was planned - to its end along the strip.
    public func follow(_ walk: PetDirector.Walk?) {
        if walk == nil, let done = self.walk, done.isOver(at: Date()), dragStart == nil { anchor.x = walkTo; layout() }
        self.walk = walk
        guard let walk, dragStart == nil, let view = panel?.contentView else { stopTicker(); return }
        let s = currentStrip
        walkFrom = anchor.x; walkTo = s.start + CGFloat(walk.to) * s.travel
        if ticker == nil { ticker = DisplayTicker(view: view) { [weak self] in self?.step() } }
    }

    /// How far along `walk` is at `date`, 0...1 (eased as the walk is).
    static func progress(_ walk: PetDirector.Walk, at date: Date) -> CGFloat {
        guard walk.to != walk.from else { return walk.isOver(at: date) ? 1 : 0 }
        return CGFloat((walk.x(at: date) - walk.from) / (walk.to - walk.from))
    }

    private func step() {
        guard let walk, dragStart == nil else { stopTicker(); return }
        let now = Date()
        anchor.x = walkFrom + (walkTo - walkFrom) * Self.progress(walk, at: now)
        layout()
        if walk.isOver(at: now) { self.walk = nil; stopTicker() }
    }

    private func stopTicker() { ticker?.stop(); ticker = nil }

    private static func screen(at point: NSPoint) -> CGRect? {
        NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame ?? NSScreen.main?.visibleFrame
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
        let placed = Self.frame(anchor: NSPoint(x: anchor.x, y: petFrame.maxY), size: Self.bubbleSize, screen: Self.screen(at: anchor))
        let bubble = bubblePanel ?? makeBubblePanel()
        let clickable = bubbleTap != nil
        bubble.ignoresMouseEvents = !clickable
        if shownBubble?.text != text || shownBubble?.tailShift != placed.tailShift || shownBubble?.clickable != clickable {
            shownBubble = (text, placed.tailShift, clickable)
            let view = clickable ? AnyView(makeBubble(text, placed.tailShift).pointerStyle(.link)
                                            .onTapGesture { [weak self] in self?.bubbleTap?() }) : makeBubble(text, placed.tailShift)
            if let bubbleHost { bubbleHost.rootView = view } else {
                let h = NSHostingView(rootView: view)
                bubble.contentView = h
                bubbleHost = h
            }
            bubbleHost?.layoutSubtreeIfNeeded()
        }
        if bubble.frame != placed.frame { bubble.setFrame(placed.frame, display: false) }
        if !bubble.isVisible { bubble.orderFrontRegardless() }
    }

    public func hide() {
        stopTicker(); walk = nil
        panel?.orderOut(nil); bubblePanel?.orderOut(nil); bubbleText = nil; bubbleTap = nil
    }

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
            home = anchor
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

    /// `origin` moved just enough for a panel of `size` to be wholly inside the usable part of the screen it is most on
    /// (the nearest one when it is on none, after a screen was unplugged); with no `origin`, the bottom-right corner of the
    /// first screen. `screens` are visible frames (no Dock or menu bar), so the pet never ends up under the Dock.
    static func onScreen(origin: NSPoint?, size: CGSize, screens: [CGRect]) -> NSPoint {
        if let origin, !screens.isEmpty {
            let frame = CGRect(origin: origin, size: size)
            func overlap(_ s: CGRect) -> CGFloat { let i = s.intersection(frame); return i.isNull ? 0 : i.width * i.height }
            func distance(_ s: CGRect) -> CGFloat { hypot(max(s.minX - frame.midX, 0, frame.midX - s.maxX), max(s.minY - frame.midY, 0, frame.midY - s.maxY)) }
            let screen = screens.max { overlap($0) < overlap($1) }.flatMap { overlap($0) > 0 ? $0 : nil }
                ?? screens.min { distance($0) < distance($1) }!
            return NSPoint(x: min(max(origin.x, screen.minX), screen.maxX - size.width),
                           y: min(max(origin.y, screen.minY), screen.maxY - size.height))
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

/// Calls `tick` once per frame of the display that `view` is on, until stopped.
@MainActor
final class DisplayTicker: NSObject {
    private var link: CADisplayLink?
    private let tick: () -> Void

    init(view: NSView, tick: @escaping () -> Void) {
        self.tick = tick
        super.init()
        link = view.displayLink(target: self, selector: #selector(fire))
        // The panel follows its walk 30 times a second, not at the screen's rate (up to 120 Hz): moving a window costs
        // the main thread a layout each time, which a slower Mac feels.
        let rate = Float(1 / PetView.walkFrameInterval)
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: rate / 2, maximum: rate, preferred: rate)
        link?.add(to: .main, forMode: .common)
    }

    @objc private func fire() { tick() }

    func stop() { link?.invalidate(); link = nil }
}
