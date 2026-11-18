import CoreDomain
import CoreUI
import FeatureChat
import FeatureMiniApps
import SharedKit
import SwiftUI

/// The settings place: one page per section of the settings nav pane (`general`, `appearance`, `chat`, `translation`,
/// `cache`) over the shell's `AppSettings` (lib/core/widgets/quick_settings_* and the settings cards of each feature).
struct SettingsPages: View {
    let root: CompositionRoot
    let section: String

    var body: some View {
        switch section {
        case "appearance": SettingsPage(title: appString("appearance", "Appearance")) {
            SettingsCard(title: appString("appearance", "Appearance")) { AppearanceControls(shell: root.shell) }
        }
        case "pet": PetSettingsPage(root: root)
        case "chat": ChatSettingsPage(shell: root.shell, mcp: root.aiTools.mcpModel)
        case "translation": TranslationSettingsPage(root: root)
        case "cache": CacheSettingsPage(root: root)
        default: GeneralSettingsPage(root: root)
        }
    }
}

struct GeneralSettingsPage: View {
    @Environment(\.appTheme) private var theme
    let root: CompositionRoot
    @State private var autoUpdate = true
    @State private var checking: String?

    var body: some View {
        let shell = root.shell, s = shell.settings
        SettingsPage(title: appString("settings", "Settings")) {
            SettingsCard(title: appString("settingsLayout", "Layout")) {
                SettingsRow(label: appString("detailLayout", "Detail layout")) {
                    SettingsSegmented(values: [(.twoPane, appString("detailTwoPane", "Two panes")), (.tabbed, appString("detailTabbed", "Tabs"))] as [(DetailLayout, String)],
                                      value: s.detailLayout) { v in shell.updateSettings { $0.detailLayout = v } }
                }
                SettingsRow(label: appString("boardLayout", "Ticket lists")) {
                    SettingsSegmented(values: [(.board, appString("viewBoard", "Board")), (.table, appString("viewList", "List"))] as [(BoardLayout, String)],
                                      value: s.boardLayout) { v in shell.updateSettings { $0.boardLayout = v } }
                }
                SettingsRow(label: appString("dateFormat", "Date format")) {
                    SettingsSegmented(values: [("iso", "2026-05-26"), ("dmy", "26/05/2026"), ("long", "May 26, 2026")], value: s.dateFormat) { v in
                        shell.updateSettings { $0.dateFormat = v }
                    }
                }
                SettingsToggleRow(label: appString("companyTint", "Company tint"), isOn: s.companyTint) { on in
                    shell.updateSettings { $0.companyTint = on }
                }
                LanguagePicker(shell: shell)
            }
            MiniAppSettingsCard(feature: root.miniApps, liveLimit: s.miniAppLiveLimit, notifyInBackground: s.miniAppNotifyInBackground,
                                dateFormat: s.dateFormat,
                                onLiveLimit: { v in shell.updateSettings { $0.miniAppLiveLimit = v } },
                                onNotifyInBackground: { on in shell.updateSettings { $0.miniAppNotifyInBackground = on } })
            SettingsCard(title: appString("appIdentity", "App name and icon")) { AppIdentityControls(root: root) }
            SettingsCard(title: appString("appUpdatesTitle", "App updates"), subtitle: "v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")") {
                SettingsToggleRow(label: appString("autoUpdateLabel", "Update automatically"), isOn: autoUpdate) { on in
                    autoUpdate = on
                    Task { _ = await root.autoUpdate.setEnabled(on) }
                }
                HStack(spacing: theme.spacing.s8) {
                    AppButton(appString("checkForUpdates", "Check for updates"), systemImage: "arrow.triangle.2.circlepath") {
                        checking = appString("updateChecking", "Checking…")
                        Task {
                            let r = await root.update.check()
                            checking = switch r {
                            case .success(let u): u == nil ? appString("updateUpToDate", "You're up to date.") : appString("updateFound", "A new version is available.")
                            case .failure(let f): f.message
                            }
                        }
                    }
                    if let checking { Text(checking).font(theme.typography.meta).foregroundStyle(theme.colors.tx3) }
                }
            }
        }
        .task {
            autoUpdate = (await root.autoUpdate.isEnabled()).value ?? true
        }
    }
}
