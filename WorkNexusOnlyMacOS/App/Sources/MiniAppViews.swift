import AppKit
import CoreDomain
import CoreUI
import FeatureMiniApps
import SharedKit
import SwiftUI
import CoreTools

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_rail_section.dart — one rail button per mini app
/// (its icon, or the name's initial) and "Add". Dragged onto another button it takes that place; the context menu edits it,
/// closes a running page (to free memory) or removes it, after asking.
struct MiniAppRailSection: View {
    @Environment(\.appTheme) private var theme
    let feature: MiniAppsFeature
    let nav: AppNavController
    @State private var adding = false
    @State private var editing: MiniApp?
    @State private var removing: MiniAppRailItem?

    var body: some View {
        let model = feature.model
        VStack(spacing: theme.spacing.s2) {
            ForEach(model.railItems) { item in
                RailLabeledButton(label: item.name, selected: item.selected, help: item.name) {
                    nav.openMiniApp(item.id)
                } leading: {
                    MiniAppRailIcon(name: item.name, iconPath: item.iconPath).opacity(item.running ? 1 : 0.7)
                }
                .draggable(item.id)
                .dropDestination(for: String.self) { dropped, _ in
                    guard let id = dropped.first, id != item.id else { return false }
                    Task { await model.move(id: id, onto: item.id) }
                    return true
                }
                .contextMenu {
                    Button(appString("miniAppEdit", "Edit mini app")) { editing = model.apps.first { $0.id == item.id } }
                    if item.running {
                        Button(appString("miniAppClose", "Close page (free memory)")) {
                            if nav.state.miniAppId == item.id { nav.select(.workspace) }
                            model.close(item.id)
                        }
                    }
                    Divider()
                    Button(appString("miniAppRemove", "Remove from rail"), role: .destructive) { removing = item }
                }
            }
            RailLabeledButton(appString("miniAppAddShort", "Add"), systemImage: "plus.app", help: appString("miniAppAdd", "Add mini app")) {
                adding = true
            }
        }
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
