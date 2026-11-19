import Foundation

/// Ported from: lib/core/config/app_config.dart (the update-related constants only).
/// Release identity the updater looks at; override for a fork or a staging build.
public struct AppUpdateConfig: Sendable, Equatable {
    public var appName: String
    public var githubOwner: String
    public var githubRepo: String
    /// Release asset holding the zipped `.app`.
    public var macAssetName: String
    /// Release asset listing `sha256  filename` lines the download is verified against.
    public var checksumsAsset: String
    /// When set (`+mac`), only releases whose tag ends with it are this app's: the release notes of the others (another
    /// app's builds in the same repository) are never shown. Nil takes every stable release.
    public var releaseTagSuffix: String?

    public init(appName: String = "WorkNexus", githubOwner: String = "thanhnguyen293", githubRepo: String = "WorkNexus",
                macAssetName: String = "WorkNexus-macos-universal.zip", checksumsAsset: String = "SHA256SUMS.txt",
                releaseTagSuffix: String? = nil) {
        self.appName = appName; self.githubOwner = githubOwner; self.githubRepo = githubRepo
        self.macAssetName = macAssetName; self.checksumsAsset = checksumsAsset; self.releaseTagSuffix = releaseTagSuffix
    }

    public var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest")!
    }

    /// The newest hundred releases, notes included.
    public var releasesURL: URL {
        URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases?per_page=100")!
    }

    /// Whether `tag` names one of this app's releases (see `releaseTagSuffix`).
    public func isOwnRelease(_ tag: String) -> Bool {
        guard let releaseTagSuffix, !releaseTagSuffix.isEmpty else { return true }
        return tag.hasSuffix(releaseTagSuffix)
    }
}
