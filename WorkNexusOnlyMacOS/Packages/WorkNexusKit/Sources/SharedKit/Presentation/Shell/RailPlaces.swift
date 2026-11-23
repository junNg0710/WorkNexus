/// Not in the Flutter app.
import AppKit
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// A place of the rail that a keyboard shortcut can open: the dashboard, Chat, a tool's sections, an account, a mini app
/// or a Mac app, Settings. `id` stays the same for as long as the place exists, so keys chosen for it stay with it.
public struct RailPlace: Identifiable {
    public let id: String
    public let name: String
    public let open: () -> Void

    public init(id: String, name: String, open: @escaping () -> Void) {
        self.id = id; self.name = name; self.open = open
    }

    static let workspace = "workspace", chat = "chat", settings = "settings"
    static func section(_ provider: ProviderType, _ section: SectionID) -> String { "section:\(provider.rawValue):\(section.rawValue)" }
    static func account(_ id: String) -> String { "account:\(id)" }
}

public extension ShellModel {
    /// The places of the rail, from the top, as the rail draws them (`NavRail`).
    var railPlaces: [RailPlace] {
        let nav = nav
        var out = [RailPlace(id: RailPlace.workspace, name: appString("dashboard", "Dashboard")) { nav.select(.workspace) }]
        if chatAccount != nil { out.append(RailPlace(id: RailPlace.chat, name: appString("chat", "Chat")) { nav.select(.chat) }) }
        for entry in railSectionTools {
            for section in entry.module.sections.filter(\.available) {
                out.append(RailPlace(id: RailPlace.section(entry.module.providerType, section.id), name: appString(section.label, section.label.capitalized)) { [weak self] in
                    self?.openRailSection(section.id, tool: entry.module, accounts: entry.accounts)
                })
            }
        }
        let accounts = railAccounts
        for a in accounts {
            let duplicate = accounts.filter { $0.providerType == a.providerType }.count > 1
            let name = duplicate ? "\(a.providerType.displayName) · \(a.handle)" : a.providerType.displayName
            out.append(RailPlace(id: RailPlace.account(a.id), name: name) { nav.select(.account(a.id)) })
        }
        out += host.railExtraPlaces()
        out.append(RailPlace(id: RailPlace.settings, name: appString("settings", "Settings")) { nav.select(.settings) })
        return out
    }

    /// The keys that open each place of the rail, by the place's id.
    var railShortcuts: [String: KeyShortcut] {
        ResolveRailShortcuts()(places: railPlaces.map(\.id), settings: settings.railShortcuts)
    }

    /// Goes to the place these keys open, and says whether there was one. A dialog keeps its keys.
    func handleRailShortcut(_ keys: KeyShortcut) -> Bool {
        guard settings.railShortcuts.enabled, !dialogs.isPresenting else { return false }
        let places = railPlaces
        let byPlace = ResolveRailShortcuts()(places: places.map(\.id), settings: settings.railShortcuts)
        guard let place = places.first(where: { byPlace[$0.id] == keys }) else { return false }
        railGate.run(place.open)
        return true
    }
}

/// Offers the keys pressed in its window to `handle` before any view sees them, whichever view has the focus (a web page,
/// a text field): the shortcuts of the rail's places. Keys that cannot be such a shortcut are passed on untouched, as are
/// those pressed while a shortcut is being chosen or an input method is composing. It also tells `held` which modifiers
/// are down in its window (none once the window or the app is left), for the rail's key hints.
struct RailShortcutMonitor: NSViewRepresentable {
    let handle: (KeyShortcut) -> Bool
    let held: (KeyShortcut.Modifiers) -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) { view.handle = handle; view.held = held }

    final class MonitorView: NSView {
        var handle: (KeyShortcut) -> Bool = { _ in false }
        var held: (KeyShortcut.Modifiers) -> Void = { _ in }
        private var token: Any?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            stop()
            guard let window else { return }
            token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                guard let self else { return event }
                if event.type == .flagsChanged {
                    let here = event.window === self.window && !ShortcutRecording.isActive
                    self.held(here ? KeyShortcut.Modifiers(event.modifierFlags) : [])
                    return event
                }
                guard event.window === self.window, !ShortcutRecording.isActive,
                      let keys = KeyShortcut(event: event), keys.problem == nil,
                      !((event.window?.firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false) else { return event }
                return self.handle(keys) ? nil : event
            }
            // Left with a modifier still down (⌘Tab to another app): its release is never seen here.
            let center = NotificationCenter.default
            observers = [(NSApplication.didResignActiveNotification, nil as AnyObject?), (NSWindow.didResignKeyNotification, window)].map { name, object in
                center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.held([]) }
                }
            }
        }

        private func stop() {
            if let token { NSEvent.removeMonitor(token) }
            token = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }
        deinit {
            if let token { NSEvent.removeMonitor(token) }
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
