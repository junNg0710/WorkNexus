import CoreUI
import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_settings_card.dart (`_DataActions`)
/// The buttons that clear the cache and all browsing data, each with what it does; disabled (and said so) where the platform
/// cannot clear.
struct MiniAppDataActions: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let model: MiniAppBrowsingDataModel
    let apps: [MiniApp]
    @State private var confirmingAll = false

    var body: some View {
        let enabled = model.canClear && model.running == nil
        VStack(alignment: .leading, spacing: theme.spacing.s12) {
            action(hint: appString("miniAppClearCacheHint", "Sign-ins stay; pages load afresh.")) {
                AppButton(appString("miniAppClearCache", "Clear cache"), systemImage: "wind", action: { Task { report(await model.clearCache(apps)) } })
                    .disabled(!enabled).opacity(enabled ? 1 : 0.5)
            }
            action(hint: appString("miniAppClearAllHint", "Signs you out of every mini app.")) {
                AppButton(appString("miniAppClearAll", "Clear all browsing data"), systemImage: "trash", kind: .danger, action: { confirmingAll = true })
                    .disabled(!enabled).opacity(enabled ? 1 : 0.5)
            }
            if !model.canClear { AppInlineNote(appString("miniAppClearUnsupported", "Clearing data is only available on Windows.")) }
        }
        .appConfirmDialog(isPresented: $confirmingAll, title: appString("miniAppClearAllTitle", "Clear all browsing data?"),
                          message: appString("miniAppClearAllMessage", "You will be signed out of every mini app. This cannot be undone."),
                          confirmLabel: appString("miniAppClear", "Clear"), destructive: true) { Task { report(await model.clearAll(apps)) } }
    }

    private func action<B: View>(hint: String, @ViewBuilder button: () -> B) -> some View {
        HStack(spacing: theme.spacing.s16) {
            button()
            Text(hint).font(theme.typography.meta).foregroundStyle(theme.colors.tx2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func report(_ ok: Bool) { MiniAppDataReport.show(ok, toasts) }
}

/// Tells the user how clearing went.
enum MiniAppDataReport {
    @MainActor static func show(_ ok: Bool, _ toasts: AppToastController?) {
        toasts?.show(ok ? appString("miniAppCleared", "Browsing data cleared") : appString("miniAppClearFailed", "Could not clear the data"),
                     kind: ok ? .success : .error)
    }
}
