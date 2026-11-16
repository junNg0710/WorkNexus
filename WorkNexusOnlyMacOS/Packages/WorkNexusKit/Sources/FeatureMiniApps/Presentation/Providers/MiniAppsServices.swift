import CoreDomain
import CoreUI
import Foundation

/// What the user can tune for mini apps (`AppSettings.miniAppLiveLimit` / `miniAppNotifyInBackground`), read at use so a
/// change applies without rebuilding the feature.
public struct MiniAppsSettings: Sendable {
    public var liveLimit: @Sendable () -> Int
    public var notifyInBackground: @Sendable () -> Bool
    public init(liveLimit: @escaping @Sendable () -> Int = { 5 }, notifyInBackground: @escaping @Sendable () -> Bool = { true }) {
        self.liveLimit = liveLimit; self.notifyInBackground = notifyInBackground
    }
}

/// Everything the mini apps' presentation depends on — interfaces and use cases only (rules 1.3/8.2).
struct MiniAppsServices: Sendable {
    var apps: MiniAppRepository
    var permissions: MiniAppPermissionRepository
    var trusted: TrustedCertificateRepository
    var addMiniApp: AddMiniApp
    var updateMiniApp: UpdateMiniApp
    var moveMiniApp: MoveMiniApp
    var resolvePermission: ResolveMiniAppPermission
    var isPinnedCertificate: IsPinnedCertificate
    var findSavedWebLogin: FindSavedWebLogin
    /// The passwords saved for the sites the mini apps open (the keychain's).
    var webLogins: WebLoginServices
    var notifier: DesktopNotifying
    var settings: MiniAppsSettings
}

/// A link a mini app was asked to open. `seq` tells a repeated request for the same address from one already handled.
struct MiniAppNavigation: Equatable {
    var id: String
    var url: String
    var seq: Int
}

/// What a notification's payload starts with, so a tap on it finds its mini app again.
private let notificationPayloadPrefix = "mini:"

func miniAppNotificationPayload(_ miniAppId: String) -> String { notificationPayloadPrefix + miniAppId }

/// The mini app a tapped notification belongs to; nil for any other.
func miniAppId(ofNotificationPayload payload: String) -> String? {
    payload.hasPrefix(notificationPayloadPrefix) ? String(payload.dropFirst(notificationPayloadPrefix.count)) : nil
}
