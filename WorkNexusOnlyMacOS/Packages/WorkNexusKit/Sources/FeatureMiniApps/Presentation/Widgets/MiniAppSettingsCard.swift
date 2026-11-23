import CoreUI
import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_settings_card.dart
/// Settings' "Mini apps" card, folded like the translation one: collapsed it says how many keep running and how many there
/// are; open it holds how many keep running, whether the ones that notify keep running hidden, clearing what their pages keep,
/// the imported cookies, the saved passwords, the trusted certificates and each app's own data. The two preferences live in the app's settings, so
/// the page that hosts the card passes them in. Needs no environment but the theme, the dialog host and the toasts.
public struct MiniAppSettingsCard: View {
    /// The numbers of pages kept running to pick from.
    public static let liveLimits = [3, 5, 8]

    let feature: MiniAppsFeature
    let liveLimit: Int
    let notifyInBackground: Bool
    let dateFormat: String
    let onLiveLimit: (Int) -> Void
    let onNotifyInBackground: (Bool) -> Void
    let initiallyExpanded: Bool

    public init(feature: MiniAppsFeature, liveLimit: Int, notifyInBackground: Bool, dateFormat: String = "iso", initiallyExpanded: Bool = false,
                onLiveLimit: @escaping (Int) -> Void, onNotifyInBackground: @escaping (Bool) -> Void) {
        self.feature = feature; self.liveLimit = liveLimit; self.notifyInBackground = notifyInBackground; self.dateFormat = dateFormat
        self.initiallyExpanded = initiallyExpanded; self.onLiveLimit = onLiveLimit; self.onNotifyInBackground = onNotifyInBackground
    }

    public var body: some View {
        let apps = feature.model.apps
        AppExpandableCard(icon: "macwindow", title: appString("miniAppSettingsTitle", "Mini apps"),
                          summary: appFormat("miniAppSettingsSummary", "Up to %1$@ running · %2$@ apps", "\(liveLimit)", "\(apps.count)"),
                          initiallyExpanded: initiallyExpanded) {
            AppExpandableCardSection(title: appString("miniAppLiveLimitLabel", "Apps kept running"),
                                     hint: appString("miniAppLiveLimitHint", "Past this, the app left longest ago closes and reopens where it was when you come back. Fewer uses less memory."),
                                     trailing: {
                AppSegmentedTabs(limits.map { n in AppSegmentedTab(label: "\(n)", active: n == liveLimit) { onLiveLimit(n) } })
            })
            AppExpandableCardSection(title: appString("miniAppNotifyBackgroundLabel", "Keep apps that notify running"),
                                     hint: appString("miniAppNotifyBackgroundHint", "Off: hidden apps pause, and their notifications wait until you open them."),
                                     trailing: {
                Toggle("", isOn: Binding(get: { notifyInBackground }, set: onNotifyInBackground)).labelsHidden().toggleStyle(.switch).controlSize(.small)
            })
            AppExpandableCardSection(title: appString("miniAppDataSection", "Browsing data"),
                                     hint: appString("miniAppDataHint", "Cache, cookies and what sites keep on this device."), content: {
                MiniAppDataActions(model: feature.browsingDataModel, apps: apps)
            })
            AppExpandableCardSection(title: appString("miniAppCookiesSection", "Imported cookies"),
                                     hint: appString("miniAppCookiesHint", "Sign mini apps in with the cookies a browser on this device already has. Only the sites you pick are imported."),
                                     content: { MiniAppCookieImportsSection(cookies: feature.cookies, dateFormat: dateFormat) })
            AppExpandableCardSection(title: appString("miniAppPasswordsSection", "Saved passwords"),
                                     hint: appString("miniAppPasswordsHint", "Sign-ins you chose to save inside mini apps, kept in your Mac's keychain and filled only on the site they were saved on."),
                                     content: { MiniAppSavedPasswordsSection(model: feature.webLoginsModel) })
            AppExpandableCardSection(title: appString("miniAppTrustedCertsSection", "Trusted certificates"),
                                     hint: appString("miniAppTrustedCertsHint", "Sites whose invalid certificate you chose to trust. They load without asking again, until you forget them here."),
                                     content: { MiniAppTrustedCertificatesSection(model: feature.trustedModel) })
            AppExpandableCardSection(title: appString("railOrderSettingsTitle", "Order on the rail"),
                                     hint: appString("railOrderSettingsHint", "Websites and Mac apps share one order. Move one up or down here, or drag it onto another on the rail."), content: {
                RailOrderSettingsList(rail: feature.rail)
            })
            AppExpandableCardSection(title: appString("miniAppSettingsApps", "Your mini apps"),
                                     hint: appString("miniAppSettingsAppsHint", "Edit a mini app, or clear one site's data."), content: {
                MiniAppSettingsAppList(feature: feature, apps: apps)
            })
            AppExpandableCardSection(title: appString("nativeAppSettingsTitle", "Mac apps"),
                                     hint: appString("nativeAppSettingsHint", "Apps on this Mac that open, or come forward, from the rail."), content: {
                NativeAppSettingsList(model: feature.nativeApps)
            })
        }
    }

    /// The choices, with the current limit among them when it is one the card does not offer.
    private var limits: [Int] { Set(Self.liveLimits + [liveLimit]).sorted() }
}
