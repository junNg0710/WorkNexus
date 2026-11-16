import CoreUI
import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_settings_app_list.dart
/// The mini apps card's list of apps, in rail order: each one's site, a way to edit it (and its permissions) and to clear what
/// it keeps.
struct MiniAppSettingsAppList: View {
    @Environment(\.appTheme) private var theme
    let feature: MiniAppsFeature
    let apps: [MiniApp]
    @State private var editing: MiniApp?

    var body: some View {
        VStack(spacing: theme.spacing.s4) {
            if apps.isEmpty {
                AppInlineNote(appString("miniAppSettingsEmpty", "No mini apps yet. Add one with + on the rail."))
            } else {
                ForEach(apps) { app in MiniAppSettingsAppRow(app: app, model: feature.browsingDataModel) { editing = app } }
            }
        }
        .appDialog(item: $editing) { app in
            MiniAppDialog(feature: feature, existing: app) { editing = nil }
        }
    }
}

private struct MiniAppSettingsAppRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let app: MiniApp
    let model: MiniAppBrowsingDataModel
    let onEdit: () -> Void
    @State private var confirming = false

    var body: some View {
        let busy = model.running == app.id
        let enabled = model.canClear && model.running == nil
        HStack(spacing: theme.spacing.s12) {
            MiniAppIconView(app: app, size: theme.sizes.icon24)
            VStack(alignment: .leading, spacing: 0) {
                Text(app.name).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                Text(URL(string: app.url)?.host ?? app.url).font(theme.typography.meta).foregroundStyle(theme.colors.tx3).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AppIconButton("pencil", help: appString("miniAppEdit", "Edit mini app"), action: onEdit)
            if busy { ProgressView().controlSize(.small).frame(width: theme.sizes.control32) }
            else {
                AppIconButton("eraser", help: model.canClear ? appString("miniAppClearSite", "Clear site data")
                                                              : appString("miniAppClearUnsupported", "Clearing data is only available on Windows.")) { confirming = true }
                    .disabled(!enabled).opacity(enabled ? 1 : 0.4)
            }
        }
        .padding(.vertical, theme.spacing.s4)
        .appConfirmDialog(isPresented: $confirming, title: appFormat("miniAppClearSiteTitle", "Clear %1$@'s data?", app.name),
                          message: appString("miniAppClearSiteMessage", "The site's cookies, storage and cache are deleted, and you are signed out of it."),
                          confirmLabel: appString("miniAppClear", "Clear"), destructive: true) {
            Task { MiniAppDataReport.show(await model.clearSite(app), toasts) }
        }
    }
}
