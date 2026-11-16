import CoreUI
import SwiftUI

/// New feature, no Dart counterpart. The mini apps card's list of Mac apps, in rail order: each one's icon, name and place, a
/// way to take it off the rail (asking first) and one to add another.
struct NativeAppSettingsList: View {
    @Environment(\.appTheme) private var theme
    let model: NativeAppsModel
    @State private var adding = false
    @State private var removing: NativeApp?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            if model.apps.isEmpty {
                AppInlineNote(appString("nativeAppSettingsEmpty", "No Mac apps yet. Add one with + on the rail."))
            }
            ForEach(model.apps) { app in
                NativeAppSettingsRow(app: app, model: model, missing: model.missingIds.contains(app.id)) { removing = app }
            }
            AppButton(appString("nativeAppAddMenuMac", "Add Mac app…"), systemImage: "plus", kind: .secondary) { adding = true }
                .padding(.top, theme.spacing.s6)
        }
        .task { model.start() }
        .appDialog(isPresented: $adding) { NativeAppPickerDialog(model: model) { adding = false } }
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
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s12) {
            NativeAppRailIcon(icon: model.icon(forPath: app.path), running: false, missing: missing)
            VStack(alignment: .leading, spacing: 0) {
                Text(app.name).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                Text(missing ? appFormat("nativeAppMissing", "%1$@ was not found. It may have been moved or uninstalled.", app.name) : app.path)
                    .font(theme.typography.meta).foregroundStyle(missing ? theme.colors.red : theme.colors.tx3)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AppIconButton("trash", help: appString("miniAppRemove", "Remove from rail"), action: onRemove)
        }
        .padding(.vertical, theme.spacing.s4)
    }
}
