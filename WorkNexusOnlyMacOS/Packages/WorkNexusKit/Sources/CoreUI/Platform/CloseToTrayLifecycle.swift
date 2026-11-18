import AppKit

/// Ported from: lib/core/platform/desktop_app_lifecycle.dart
/// Coordinates the window's close button with the status item: while the tray is ready, closing the window hides it
/// instead of ending the app; "Open" brings it back, "Quit" really quits.
@MainActor
public final class CloseToTrayLifecycle: NSObject, NSWindowDelegate {
    private let tray: StatusItemService
    private weak var window: NSWindow?
    private weak var previousDelegate: NSWindowDelegate?
    private var quitting = false
    private let terminate: @MainActor () -> Void

    public private(set) var isTrayReady = false

    public init(tray: StatusItemService? = nil, terminate: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }) {
        self.tray = tray ?? StatusItemService(); self.terminate = terminate
    }

    /// Installs the tray item and starts intercepting `window`'s close. Other delegate callbacks keep reaching the
    /// delegate SwiftUI/AppKit had installed.
    public func initialize(window: NSWindow, strings: StatusItemStrings = StatusItemStrings(), icon: NSImage? = StatusItemService.bundledIcon()) {
        self.window = window
        tray.updateStrings(strings)
        isTrayReady = tray.initialize(icon: icon, onOpen: { [weak self] in self?.open() }, onQuit: { [weak self] in self?.quit() })
        guard isTrayReady else { return }
        if window.delegate !== self { previousDelegate = window.delegate; window.delegate = self }
    }

    public func setTrayIcon(_ image: NSImage?) { tray.setIcon(image) }
    public func setTrayToolTip(_ name: String?) { tray.setToolTip(name) }
    public func updateStrings(_ strings: StatusItemStrings) { tray.updateStrings(strings) }
    /// The on/off item of the tray menu (show / hide the pet); nil takes it out.
    public func setTrayToggle(_ toggle: StatusItemToggle?) { tray.setToggle(toggle) }

    public func open() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    public func quit() {
        guard !quitting else { return }
        quitting = true
        window?.delegate = previousDelegate
        tray.dispose()
        terminate()
    }

    // MARK: NSWindowDelegate

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isTrayReady && !quitting {
            sender.orderOut(nil)
            return false
        }
        return previousDelegate?.windowShouldClose?(sender) ?? true
    }

    public override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let previousDelegate, previousDelegate.responds(to: aSelector) { return previousDelegate }
        return super.forwardingTarget(for: aSelector)
    }

    public override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (previousDelegate?.responds(to: aSelector) ?? false)
    }
}
