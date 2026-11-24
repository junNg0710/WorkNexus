import AppKit
import CoreDomain
import CoreUI
import FeatureMiniApps
import SharedKit
import SwiftUI
import CoreTools

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_rail_section.dart — the rail's own apps and "Add".
/// Websites (mini apps) and Mac apps share one order here (`RailAppsModel`): one button each, wherever the user put it.
/// Dragged onto another button it takes that place, whatever the kind of either; the context menu moves it a step up or
/// down, edits it and removes it, after asking. "Add" is a menu: a website (the mini-app dialog) or a Mac app.
struct MiniAppRailSection: View {
    @Environment(\.appTheme) private var theme
    let feature: MiniAppsFeature
    let nav: AppNavController
    /// The keyboard shortcut of a place of the rail (`RailAppRef.id`), as shown in its tooltip; nil: none.
    var keys: (String) -> String? = { _ in nil }
    /// The key that place shows on its button while the shortcut's modifiers are held; nil: nothing.
    var keyHint: (String) -> String? = { _ in nil }
    @State private var adding = false
    @State private var addingMacApp = false
    @State private var editing: MiniApp?
    @State private var removing: MiniAppRailItem?
    @State private var editingMacApp: NativeApp?
    @State private var removingMacApp: NativeAppRailItem?

    var body: some View {
        let model = feature.model, rail = feature.rail
        VStack(spacing: theme.spacing.s2) {
            ForEach(rail.items) { entry in
                switch entry {
                case .miniApp(let item):
                    MiniAppRailButton(item: item, rail: rail, nav: nav, keys: keys(entry.id), keyHint: keyHint(entry.id),
                                      onEdit: { editing = model.apps.first { $0.id == item.id } }) { removing = item }
                case .nativeApp(let item):
                    NativeAppRailButton(item: item, rail: rail, keyHint: keyHint(entry.id),
                                        onEdit: { editingMacApp = $0 }) { removingMacApp = item }
                }
            }
            RailLabeledButton(appString("miniAppAddShort", "Add"), systemImage: "plus.app", help: appString("nativeAppAddHelp", "Add a website or a Mac app")) {
                RailPopupMenu.show([(appString("nativeAppAddMenuWebsite", "Add website…"), "globe", { adding = true }),
                                    (appString("nativeAppAddMenuMac", "Add Mac app…"), "app.badge", { addingMacApp = true })])
            }
        }
        .modifier(NativeAppRailDialogs(model: feature.nativeApps, removing: $removingMacApp, editing: $editingMacApp))
        .appDialog(isPresented: $addingMacApp) { NativeAppPickerDialog(model: feature.nativeApps) { addingMacApp = false } }
        .appDialog(isPresented: $adding) {
            // A new app opens at once, as picking it on the rail would.
            MiniAppDialog(feature: feature, onSaved: { nav.openMiniApp($0.id) }) { adding = false }
        }
        .appDialog(item: $editing) { app in
            MiniAppDialog(feature: feature, existing: app) { editing = nil }
        }
        .appConfirmDialog(isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                          title: appFormat("miniAppRemoveTitle", "Remove %1$@?", removing?.name ?? ""),
                          message: appString("miniAppRemoveMessage", "It only leaves the rail. The website itself is not affected."),
                          confirmLabel: appString("miniAppRemove", "Remove from rail"), destructive: true) {
            guard let item = removing else { return }
            if nav.state.miniAppId == item.id { nav.select(.workspace) }
            Task { await feature.model.remove(item.id) }
        }
    }
}

/// A mini app's button: its icon, or the name's initial. A click shows its page; the context menu edits it, closes a
/// running page (to free memory), moves it or removes it.
private struct MiniAppRailButton: View {
    let item: MiniAppRailItem
    let rail: RailAppsModel
    let nav: AppNavController
    let keys: String?
    let keyHint: String?
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        RailLabeledButton(label: item.name, selected: item.selected, help: keys.map { "\(item.name) (\($0))" } ?? item.name) {
            nav.openMiniApp(item.id)
        } leading: {
            MiniAppRailIcon(name: item.name, iconPath: item.iconPath).opacity(item.running ? 1 : 0.7)
        }
        .modifier(RailAppPlace(rail: rail, ref: .miniApp(item.id), keyHint: keyHint))
        .contextMenu {
            Button(appString("miniAppEdit", "Edit mini app"), action: onEdit)
            if item.running {
                Button(appString("miniAppClose", "Close page (free memory)")) {
                    if nav.state.miniAppId == item.id { nav.select(.workspace) }
                    rail.miniApps.close(item.id)
                }
            }
            Divider()
            RailMoveMenuItems(rail: rail, ref: .miniApp(item.id))
            Divider()
            Button(appString("miniAppRemove", "Remove from rail"), role: .destructive, action: onRemove)
        }
    }
}

/// What a website's and a Mac app's button share as a place of the rail: the key hint, and the drag and drop that
/// reorders - dropped on another button, of either kind, it takes that place.
struct RailAppPlace: ViewModifier {
    let rail: RailAppsModel
    let ref: RailAppRef
    let keyHint: String?

    func body(content: Content) -> some View {
        content
            .railKeyHint(keyHint)
            .draggable(ref.id)
            .dropDestination(for: String.self) { dropped, _ in rail.drop(dropped.first, onto: ref) }
    }
}

/// "Move up" / "Move down" of a rail button's context menu: one place within the websites and Mac apps together.
struct RailMoveMenuItems: View {
    let rail: RailAppsModel
    let ref: RailAppRef

    var body: some View {
        Button(appString("nativeAppMoveUp", "Move up")) { Task { await rail.move(ref, by: -1) } }
            .disabled(!rail.canMove(ref, by: -1))
        Button(appString("nativeAppMoveDown", "Move down")) { Task { await rail.move(ref, by: 1) } }
            .disabled(!rail.canMove(ref, by: 1))
    }
}

private struct MiniAppRailIcon: View {
    @Environment(\.appTheme) private var theme
    let name: String; let iconPath: String?
    var body: some View {
        Group {
            if let iconPath, let image = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Text(String(name.first.map { String($0).uppercased() } ?? "?")).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.colors.accentTx).frame(width: 22, height: 22).background(theme.colors.accent)
            }
        }
        .frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: theme.radii.sm))
    }
}

/// The mounted mini app pages. The fold of the bars over them is one of the app's settings, which the shell's title bar
/// follows too (`ShellModel.titleBarHidden`), so one button folds both.
struct MiniAppStackHost: View {
    let shell: ShellModel
    var body: some View {
        MiniAppsHostStack(bars: MiniAppBars(collapsed: shell.settings.miniAppBarsCollapsed) { collapsed in
            shell.updateSettings { $0.miniAppBarsCollapsed = collapsed }
        })
    }
}
