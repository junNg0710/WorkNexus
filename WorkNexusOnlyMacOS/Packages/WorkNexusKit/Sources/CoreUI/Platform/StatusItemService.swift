import AppKit

/// Ported from: lib/core/platform/desktop_tray_service.dart
/// Labels of the tray menu. Defaults resolve `trayOpenApp` / `trayQuitApp` from the app's `Localizable.xcstrings`.
public struct StatusItemStrings: Sendable, Equatable {
    public var openApp: String
    public var quitApp: String
    public init(openApp: String = String(localized: "trayOpenApp"), quitApp: String = String(localized: "trayQuitApp")) {
        self.openApp = openApp; self.quitApp = quitApp
    }
}

/// An item of the tray menu between "Open" and "Quit" that turns something on or off (the pet): its title says what a
/// click does ("Show the pet" / "Hide the pet"). Not in the Flutter app.
public struct StatusItemToggle {
    public var title: String
    /// An SF Symbol shown before the title.
    public var systemImage: String?
    public var action: () -> Void

    public init(title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.action = action
    }
}

/// Owns the menu-bar status item and translates its menu clicks into app actions. Clicking the icon pops the menu
/// (Open / Quit), as the Flutter tray does on macOS.
@MainActor
public final class StatusItemService: NSObject {
    private var item: NSStatusItem?
    private var onOpen: (() async -> Void)?
    private var onQuit: (() async -> Void)?
    private var strings: StatusItemStrings
    private var toolTip: String?
    private var toggle: StatusItemToggle?

    public var isReady: Bool { item != nil }

    public init(strings: StatusItemStrings = StatusItemStrings()) { self.strings = strings }

    /// The tray glyph shipped in the app bundle (`Tray/app_icon.png`), sized for the menu bar.
    public nonisolated static func bundledIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "app_icon", withExtension: "png", subdirectory: "Tray") else { return nil }
        return NSImage(contentsOf: url)
    }

    @discardableResult
    public func initialize(icon: NSImage? = StatusItemService.bundledIcon(), toolTip: String? = nil,
                           onOpen: @escaping () async -> Void, onQuit: @escaping () async -> Void) -> Bool {
        dispose()
        self.onOpen = onOpen; self.onQuit = onQuit
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item = status
        setIcon(icon)
        setToolTip(toolTip)
        status.menu = makeMenu()
        return true
    }

    /// Shows `name` as the tray tooltip, or the app's own name for nil.
    public func setToolTip(_ name: String?) {
        toolTip = name
        item?.button?.toolTip = name ?? AppIdentity.appName
    }

    /// Shows `image` in the tray, or the bundled one for nil.
    public func setIcon(_ image: NSImage?) {
        guard let button = item?.button else { return }
        let img = image ?? Self.bundledIcon()
        img?.size = NSSize(width: 18, height: 18)
        button.image = img
        if img == nil { button.title = AppIdentity.appName }
    }

    public func updateStrings(_ strings: StatusItemStrings) {
        self.strings = strings
        item?.menu = makeMenu()
    }

    /// Shows `toggle` in the menu (nil takes it out). The menu is rebuilt, so call it again whenever the title changes.
    public func setToggle(_ toggle: StatusItemToggle?) {
        self.toggle = toggle
        item?.menu = makeMenu()
    }

    /// The titles of the menu, separators as "-" (for tests).
    var menuTitles: [String] { makeMenu().items.map { $0.isSeparatorItem ? "-" : $0.title } }

    public func dispose() {
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil; onOpen = nil; onQuit = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let open = NSMenuItem(title: strings.openApp, action: #selector(openClicked), keyEquivalent: "")
        open.target = self
        let quit = NSMenuItem(title: strings.quitApp, action: #selector(quitClicked), keyEquivalent: "")
        quit.target = self
        menu.addItem(open)
        if let toggle {
            let t = NSMenuItem(title: toggle.title, action: #selector(toggleClicked), keyEquivalent: "")
            t.target = self
            t.image = toggle.systemImage.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            menu.addItem(t)
        }
        menu.addItem(.separator()); menu.addItem(quit)
        return menu
    }

    @objc private func openClicked() { if let a = onOpen { Task { await a() } } }
    @objc private func toggleClicked() { toggle?.action() }
    @objc private func quitClicked() { if let a = onQuit { Task { await a() } } }
}
