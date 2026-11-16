import Foundation

/// Ported from: lib/features/mini_apps/domain/usecases/is_mini_app_origin.dart
/// Whether `page` is on the mini app's own site (`appUrl`'s scheme, host and port). A page the app moved to on another
/// site (a sign-in, an outside link) does not get what the user allowed the app.
public struct IsMiniAppOrigin: Sendable {
    public init() {}

    public func callAsFunction(_ appUrl: String, _ page: URL?) -> Bool {
        guard let app = URL(string: appUrl), let page, let appHost = app.host, !appHost.isEmpty, let pageHost = page.host else { return false }
        return app.scheme?.lowercased() == page.scheme?.lowercased() && appHost.lowercased() == pageHost.lowercased()
            && app.port == page.port
    }
}
