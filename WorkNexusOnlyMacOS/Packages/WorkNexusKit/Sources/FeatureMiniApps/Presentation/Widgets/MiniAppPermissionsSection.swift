import CoreUI
import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_permissions_section.dart
/// The edit dialog's list of what the user allowed or blocked for this mini app: flip an answer, or have the page asked again.
struct MiniAppPermissionsSection: View {
    @Environment(\.appTheme) private var theme
    let model: MiniAppPermissionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s6) {
            Text(appString("miniAppPermissionsTitle", "Permissions")).font(theme.typography.metaStrong).foregroundStyle(theme.colors.tx2)
            if model.grants.isEmpty {
                AppInlineNote(appString("miniAppPermissionsEmpty", "None yet. When the page asks to use something, your answer shows up here."))
            } else {
                ForEach(model.grants, id: \.kind) { MiniAppGrantRow(grant: $0, model: model) }
            }
        }
        .task { await model.watch() }
    }
}

private struct MiniAppGrantRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let grant: MiniAppPermissionGrant
    let model: MiniAppPermissionsModel

    var body: some View {
        let allowed = grant.decision == .allow
        HStack(spacing: theme.spacing.s10) {
            Image(systemName: grant.kind.systemImage).font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.tx2)
                .frame(width: theme.sizes.icon20)
            Text(grant.kind.label).font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            AppSegmentedTabs([
                AppSegmentedTab(label: appString("miniAppPermissionAllowed", "Allowed"), active: allowed) { set(.allow) },
                AppSegmentedTab(label: appString("miniAppPermissionBlocked", "Blocked"), active: !allowed) { set(.block) },
            ])
            AppIconButton("arrow.counterclockwise", help: appString("miniAppPermissionReset", "Ask again")) {
                Task { report(await model.forget(grant.kind)) }
            }
        }
    }

    private func set(_ decision: MiniAppPermissionDecision) { Task { report(await model.remember(grant.kind, decision)) } }

    private func report(_ kept: Bool) {
        if !kept { toasts?.show(appString("miniAppPermissionSaveFailed", "Couldn't save your choice. You'll be asked again next time."), kind: .error) }
    }
}
