import Foundation

/// Whether a link a mini app's page opened in a window of its own belongs to the app's own site — its host or any host under
/// the same registrable domain (`files.example.com` for an app on `zentao.example.com`), on the web (`http` / `https`). Such
/// a link opens as another tab of the app; anything else (another site, a blank window) keeps the pop-up. Looser than
/// `IsMiniAppOrigin`, which is about what the user allowed a page.
public struct IsMiniAppSite: Sendable {
    public init() {}

    public func callAsFunction(_ appUrl: String, _ link: String) -> Bool {
        guard let app = Self.webHost(appUrl), let page = Self.webHost(link) else { return false }
        return app == page || cookieSite(of: app) == cookieSite(of: page)
    }

    private static func webHost(_ text: String) -> String? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return host
    }
}
