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

    public init(appName: String = "WorkNexus", githubOwner: String = "thanhnguyen293", githubRepo: String = "WorkNexus",
                macAssetName: String = "WorkNexus-macos-universal.zip", checksumsAsset: String = "SHA256SUMS.txt") {
        self.appName = appName; self.githubOwner = githubOwner; self.githubRepo = githubRepo
        self.macAssetName = macAssetName; self.checksumsAsset = checksumsAsset
    }

    public var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest")!
    }
}
