import AppKit
import CoreDomain
import CoreUI
import FeatureMiniApps
import SharedKit
import SwiftUI

/// New feature, no Dart counterpart. One rail button per Mac app (its own icon, a dot while it runs, dimmed when it went missing):
/// a click opens it or brings it forward. Dragged onto another Mac app it takes that place; the context menu opens, reveals,
/// locates (a missing one), moves and removes it, after asking.
struct NativeAppRailButtons: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let model: NativeAppsModel
    /// The key an app shows on its button while its shortcut's modifiers are held; nil: nothing.
    var keyHint: (String) -> String? = { _ in nil }
    @State private var removing: NativeAppRailItem?
    @State private var editing: NativeApp?

    /// A drag's payload starts with this, so a Mac app is never taken for a mini app (whose payload is its bare id).
    static let dragPrefix = "native:"

    var body: some View {
        VStack(spacing: theme.spacing.s2) {
            ForEach(model.railItems) { item in
                RailLabeledButton(label: item.name, badge: item.badgeCount, help: help(item)) {
                    open(item)
                } leading: {
                    NativeAppRailIcon(icon: model.icon(forPath: item.path, custom: item.iconPath), running: item.running, missing: item.missing)
                }
                .railKeyHint(keyHint(item.id))
                .draggable(Self.dragPrefix + item.id)
                .dropDestination(for: String.self) { dropped, _ in
                    guard let payload = dropped.first, payload.hasPrefix(Self.dragPrefix) else { return false }
                    let id = String(payload.dropFirst(Self.dragPrefix.count))
                    guard id != item.id else { return false }
                    Task { await model.move(id: id, onto: item.id) }
                    return true
                }
                .contextMenu { menu(item) }
            }
        }
        .task { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Off the main thread: the Dock is busy bringing the app forward just now, and may take its time to answer.
            model.refreshMissing()
            Task { await model.refreshBadgesOffMain() }
        }
        // Badges need Accessibility access, which nobody goes looking for: said once, when there is an app to show one on.
        .appConfirmDialog(isPresented: Binding(get: { model.badgeOffer != nil }, set: { if !$0 { model.declineBadgeOffer() } }),
                          title: appString("nativeAppBadgeOfferTitle", "Show notification badges on the rail?"),
                          message: model.badgeOffer == .lost
                              ? appString("nativeAppBadgeOfferLost", "macOS stopped letting WorkNexus read the Dock's badges - an update counts as a new app. In Privacy & Security → Accessibility, remove WorkNexusMac with −, then add it again and turn it on.")
                              : appString("nativeAppBadgeOfferMessage", "The Mac apps on the rail can show the same unread count as their Dock icon. macOS allows that only to apps turned on under Privacy & Security → Accessibility."),
                          confirmLabel: appString("nativeAppBadgeOpenSettings", "Open System Settings")) {
            model.requestBadgeAccess()
        }
        .appConfirmDialog(isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                          title: appFormat("miniAppRemoveTitle", "Remove %1$@?", removing?.name ?? ""),
                          message: appString("nativeAppRemoveMessage", "It only leaves the rail. The app itself is not affected."),
                          confirmLabel: appString("miniAppRemove", "Remove from rail"), destructive: true) {
            guard let item = removing else { return }
            Task { await model.remove(item.id) }
        }
        .appDialog(item: $editing) { app in NativeAppEditDialog(model: model, app: app) { editing = nil } }
    }

    private func help(_ item: NativeAppRailItem) -> String {
        if item.missing { return appFormat("nativeAppMissing", "%1$@ was not found. It may have been moved or uninstalled.", item.name) }
        if let badge = item.badge, !badge.isEmpty { return appFormat("nativeAppBadgeTip", "%1$@ · %2$@ in its Dock badge", item.name, badge) }
        return item.name
    }

    private func app(_ item: NativeAppRailItem) -> NativeApp? { model.apps.first { $0.id == item.id } }

    private func open(_ item: NativeAppRailItem) {
        guard let app = app(item) else { return }
        Task {
            if case .failure = await model.launch(app) {
                toasts?.show(item.missing ? help(item) : appFormat("nativeAppLaunchFailed", "Couldn't open %1$@", item.name), kind: .error)
            }
        }
    }

    @ViewBuilder
    private func menu(_ item: NativeAppRailItem) -> some View {
        Button(appString("nativeAppOpen", "Open")) { open(item) }.disabled(item.missing)
        if model.canShowBadges && !model.badgesAllowed {
            Button(appString("nativeAppShowBadges", "Show notification badges…")) { model.requestBadgeAccess() }
        }
        if item.missing {
            Button(appString("nativeAppLocate", "Locate…")) { locate(item) }
        } else {
            Button(appString("nativeAppReveal", "Reveal in Finder")) { app(item).map(model.reveal) }
        }
        Button(appString("nativeAppEditMenu", "Edit name and icon…")) { editing = app(item) }
        Divider()
        Button(appString("nativeAppMoveUp", "Move up")) { Task { await model.move(id: item.id, by: -1) } }
            .disabled(!model.canMove(id: item.id, by: -1))
        Button(appString("nativeAppMoveDown", "Move down")) { Task { await model.move(id: item.id, by: 1) } }
            .disabled(!model.canMove(id: item.id, by: 1))
        Divider()
        Button(appString("miniAppRemove", "Remove from rail"), role: .destructive) { removing = item }
    }

    /// Picks the app again; an app with the same identifier takes the new place, any other is added as a new button.
    private func locate(_ item: NativeAppRailItem) {
        guard let path = NativeAppPanel.chooseApp(message: appFormat("nativeAppLocateMessage", "Choose %1$@", item.name)) else { return }
        Task {
            if case .failure = await model.add(path: path) {
                toasts?.show(appString("nativeAppNotAnApp", "That is not a Mac app."), kind: .error)
            }
        }
    }
}

/// The "Add" button's menu (Add website… / Add Mac app…) as a real macOS menu popped up under the pointer: the rail is too narrow
/// to hold a menu panel of its own.
@MainActor
enum RailPopupMenu {
    static func show(_ entries: [(title: String, systemImage: String, action: () -> Void)]) {
        let menu = NSMenu()
        for entry in entries {
            let item = ClosureMenuItem(title: entry.title, action: entry.action)
            item.image = NSImage(systemSymbolName: entry.systemImage, accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private final class ClosureMenuItem: NSMenuItem {
        private let run: () -> Void
        init(title: String, action: @escaping () -> Void) {
            run = action
            super.init(title: title, action: #selector(fire), keyEquivalent: "")
            target = self
        }
        required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
        @objc private func fire() { run() }
    }
}
