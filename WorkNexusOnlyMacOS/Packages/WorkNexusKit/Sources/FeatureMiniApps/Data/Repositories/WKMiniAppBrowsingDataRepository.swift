import CoreDomain
import Foundation

/// Ported from: lib/features/mini_apps/data/repositories/local_mini_app_browsing_data_repository.dart
/// `MiniAppBrowsingDataRepository` over the web view's own profile.
public final class WKMiniAppBrowsingDataRepository: MiniAppBrowsingDataRepository, Sendable {
    public init() {}
    public var canClear: Bool { true }

    public func clearCache() async -> Outcome<Void> {
        await WebProfileDataSource().clearCache()
        return .success(())
    }

    public func clearSite(url: String) async -> Outcome<Void> {
        let hosts = Self.hosts(of: [url])
        await WebProfileDataSource().clearSites(hosts: hosts)
        return .success(())
    }

    public func clearAll(urls: [String]) async -> Outcome<Void> {
        await WebProfileDataSource().clearAll()
        return .success(())
    }

    /// The hosts of `urls`; anything that is not a web address is skipped.
    static func hosts(of urls: [String]) -> Set<String> {
        Set(urls.compactMap { u in
            guard let url = URL(string: u), url.scheme == "http" || url.scheme == "https", let host = url.host, !host.isEmpty else { return nil }
            return host.lowercased()
        })
    }
}
