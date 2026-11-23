import CoreUI
import SwiftUI

/// Not in the Flutter app. The mini apps card's "Order on the rail": the websites and the Mac apps as the one list the
/// rail shows, each with a way a step up and a step down.
struct RailOrderSettingsList: View {
    @Environment(\.appTheme) private var theme
    let rail: RailAppsModel

    var body: some View {
        let items = rail.items
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            if items.isEmpty {
                AppInlineNote(appString("railOrderSettingsEmpty", "Nothing here yet. Add a website or a Mac app with + on the rail."))
            }
            ForEach(items) { item in RailOrderSettingsRow(item: item, rail: rail) }
        }
        .task { rail.nativeApps.start() }
    }
}

private struct RailOrderSettingsRow: View {
    @Environment(\.appTheme) private var theme
    let item: RailAppItem
    let rail: RailAppsModel

    var body: some View {
        HStack(spacing: theme.spacing.s12) {
            RailOrderIcon(item: item, rail: rail)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                Text(kind).font(theme.typography.meta).foregroundStyle(theme.colors.tx3).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RailOrderStepButton(systemImage: "chevron.up", help: appString("nativeAppMoveUp", "Move up"), step: -1, item: item, rail: rail)
            RailOrderStepButton(systemImage: "chevron.down", help: appString("nativeAppMoveDown", "Move down"), step: 1, item: item, rail: rail)
        }
        .padding(.vertical, theme.spacing.s4)
    }

    private var kind: String {
        switch item {
        case .miniApp: appString("railOrderKindWebsite", "Website")
        case .nativeApp: appString("railOrderKindMacApp", "Mac app")
        }
    }
}

private struct RailOrderIcon: View {
    @Environment(\.appTheme) private var theme
    let item: RailAppItem
    let rail: RailAppsModel

    var body: some View {
        switch item {
        case .miniApp(let site):
            if let app = rail.miniApps.apps.first(where: { $0.id == site.id }) { MiniAppIconView(app: app, size: theme.sizes.icon24) }
        case .nativeApp(let app):
            NativeAppRailIcon(icon: rail.nativeApps.icon(forPath: app.path, custom: app.iconPath), running: false, missing: app.missing)
        }
    }
}

private struct RailOrderStepButton: View {
    let systemImage: String
    let help: String
    let step: Int
    let item: RailAppItem
    let rail: RailAppsModel

    var body: some View {
        let enabled = rail.canMove(item.ref, by: step)
        AppIconButton(systemImage, help: help) { Task { await rail.move(item.ref, by: step) } }
            .disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }
}
