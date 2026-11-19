import AppKit

/// Ported from: macos/Runner/PanicOverlayPanel.swift (the panic switch's floating button)
/// A sticker floating above every app: a borderless panel on every Space (beside full-screen apps too) that never takes the
/// keyboard or brings the app forward. Drag it to move it; every click that was not a drag calls `onClick` (the panic
/// switch counts three in a row). Where it was left is remembered under `autosaveKey`, and brought back onto a screen when
/// that screen is gone (`FloatingPetPanel.onScreen`).
@MainActor
public final class FloatingStickerPanel {
    /// The sticker's width on screen; the height follows the image.
    public static let width: CGFloat = 120

    public var onClick: (() -> Void)?
    private var panel: StickerPanel?
    private let defaults: UserDefaults
    private let xKey: String, yKey: String

    public init(autosaveKey: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults; xKey = "\(autosaveKey).x"; yKey = "\(autosaveKey).y"
    }

    public var isShown: Bool { panel?.isVisible == true }

    /// Shows `image` (or swaps it in while shown).
    public func show(image: NSImage) {
        let size = image.size.width > 0
            ? CGSize(width: Self.width, height: Self.width * image.size.height / image.size.width)
            : CGSize(width: Self.width, height: Self.width)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        (panel.contentView as? StickerButtonView)?.image = image
        if !panel.isVisible {
            let saved = defaults.object(forKey: xKey) != nil ? NSPoint(x: defaults.double(forKey: xKey), y: defaults.double(forKey: yKey)) : nil
            let origin = FloatingPetPanel.onScreen(origin: saved, size: size, screens: NSScreen.screens.map(\.visibleFrame))
            panel.setFrame(CGRect(origin: origin, size: size), display: true)
            panel.orderFrontRegardless()
        } else if panel.frame.size != size {
            panel.setFrame(CGRect(origin: panel.frame.origin, size: size), display: true)
        }
    }

    public func hide() { panel?.orderOut(nil) }

    private func makePanel() -> StickerPanel {
        let p = StickerPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.animationBehavior = .none
        let view = StickerButtonView()
        view.onClick = { [weak self] in self?.onClick?() }
        view.onMoved = { [weak self, weak p] in
            guard let self, let origin = p?.frame.origin else { return }
            defaults.set(Double(origin.x), forKey: xKey); defaults.set(Double(origin.y), forKey: yKey)
        }
        p.contentView = view
        return p
    }
}

/// A panel that never becomes the key or main window (typing stays where it was).
private final class StickerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The sticker itself: a click calls `onClick`, a drag (past 3 points) moves the panel and calls `onMoved` at the end.
private final class StickerButtonView: NSImageView {
    var onClick: (() -> Void)?
    var onMoved: (() -> Void)?
    private var dragStart: NSPoint?
    private var dragged = false

    init() {
        super.init(frame: .zero)
        imageScaling = .scaleProportionallyUpOrDown
        isEditable = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // A click on an inactive app's panel still counts as a click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x, dy = now.y - start.y
        if !dragged && abs(dx) < 3 && abs(dy) < 3 { return }
        dragged = true
        window.setFrameOrigin(NSPoint(x: window.frame.origin.x + dx, y: window.frame.origin.y + dy))
        dragStart = now
    }

    override func mouseUp(with event: NSEvent) {
        if dragged { onMoved?() } else { onClick?() }
        dragStart = nil
        dragged = false
    }
}
