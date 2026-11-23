import CoreUI
import SwiftUI

/// New feature, no Dart counterpart. The mini apps card's list of Mac apps, in rail order: each one's icon, name and place, a
/// way to take it off the rail (asking first) and one to add another.
struct NativeAppSettingsList: View {
    @Environment(\.appTheme) private var theme
    let model: NativeAppsModel
    @State private var adding = false
    @State private var removing: NativeApp?
    @State private var editing: NativeApp?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            if model.apps.isEmpty {
                AppInlineNote(appString("nativeAppSettingsEmpty", "No Mac apps yet. Add one with + on the rail."))
            }
            ForEach(model.apps) { app in
                NativeAppSettingsRow(app: app, model: model, missing: model.missingIds.contains(app.id),
                                     onEdit: { editing = app }) { removing = app }
            }
            AppButton(appString("nativeAppAddMenuMac", "Add Mac app…"), systemImage: "plus", kind: .secondary) { adding = true }
                .padding(.top, theme.spacing.s6)
            if model.canShowBadges, !model.apps.isEmpty { NativeAppBadgeAccessRow(model: model).padding(.top, theme.spacing.s12) }
        }
        .task { model.start(); await model.refreshBadgesOffMain() }
        .appDialog(isPresented: $adding) { NativeAppPickerDialog(model: model) { adding = false } }
        .appDialog(item: $editing) { app in NativeAppEditDialog(model: model, app: app) { editing = nil } }
        .appConfirmDialog(isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                          title: appFormat("miniAppRemoveTitle", "Remove %1$@?", removing?.name ?? ""),
                          message: appString("nativeAppRemoveMessage", "It only leaves the rail. The app itself is not affected."),
                          confirmLabel: appString("miniAppRemove", "Remove from rail"), destructive: true) {
            guard let app = removing else { return }
            Task { await model.remove(app.id) }
        }
    }
}

private struct NativeAppSettingsRow: View {
    @Environment(\.appTheme) private var theme
    let app: NativeApp
    let model: NativeAppsModel
    let missing: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s12) {
            NativeAppRailIcon(icon: model.icon(forPath: app.path, custom: app.iconPath), running: false, missing: missing)
            VStack(alignment: .leading, spacing: 0) {
                Text(app.label).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                Text(missing ? appFormat("nativeAppMissing", "%1$@ was not found. It may have been moved or uninstalled.", app.name) : app.path)
                    .font(theme.typography.meta).foregroundStyle(missing ? theme.colors.red : theme.colors.tx3)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AppIconButton("pencil", help: appString("nativeAppEditMenu", "Edit name and icon…"), action: onEdit)
            AppIconButton("trash", help: appString("miniAppRemove", "Remove from rail"), action: onRemove)
        }
        .padding(.vertical, theme.spacing.s4)
    }
}

/// Whether the rail can show the Dock's badges, and the way to System Settings while it cannot.
private struct NativeAppBadgeAccessRow: View {
    @Environment(\.appTheme) private var theme
    let model: NativeAppsModel

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.s12) {
            Image(systemName: model.badgesAllowed ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: theme.sizes.icon16)).foregroundStyle(model.badgesAllowed ? theme.colors.green : theme.colors.amber)
            VStack(alignment: .leading, spacing: theme.spacing.s4) {
                Text(appString("nativeAppBadgeSettingsTitle", "Notification badges")).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                Text(model.badgesAllowed
                     ? appString("nativeAppBadgeSettingsOn", "The rail shows each app's Dock badge.")
                     : appString("nativeAppBadgeSettingsOff", "Off: macOS has not let WorkNexus read the Dock. Turn WorkNexusMac on under Privacy & Security → Accessibility. Already on there? Remove it with − and add it again - an update counts as a new app."))
                    .font(theme.typography.meta).foregroundStyle(theme.colors.tx3).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !model.badgesAllowed {
                AppButton(appString("nativeAppBadgeOpenSettings", "Open System Settings"), kind: .secondary) { model.requestBadgeAccess() }
            }
        }
    }
}
