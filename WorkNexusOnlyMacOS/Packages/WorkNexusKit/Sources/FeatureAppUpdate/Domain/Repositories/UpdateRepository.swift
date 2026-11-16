import CoreDomain

/// Ported from: lib/features/app_update/domain/repositories/update_repository.dart
public struct UpdateVersionSnapshot: Sendable, Equatable {
    public var currentVersion: String
    public var latestVersion: String
    public var releaseUrl: String
    public var releaseNotes: String
    public var downloadUrl: String?
    public var sha256: String?

    public init(currentVersion: String, latestVersion: String, releaseUrl: String, releaseNotes: String,
                downloadUrl: String?, sha256: String?) {
        self.currentVersion = currentVersion; self.latestVersion = latestVersion; self.releaseUrl = releaseUrl
        self.releaseNotes = releaseNotes; self.downloadUrl = downloadUrl; self.sha256 = sha256
    }
}

public protocol UpdateRepository: Sendable {
    /// The version of the running build (`1.4.1`).
    func currentVersion() -> String
    func fetchLatestStableRelease() async -> Outcome<UpdateVersionSnapshot?>
    /// Downloads, verifies the checksum and unpacks; returns the path of the staged build.
    func download(_ update: AvailableUpdate, onProgress: @escaping @Sendable (Double) -> Void) async -> Outcome<String>
    /// Swaps the staged build in for the running one and restarts the app. Only returns when the install could not start.
    func install(stagedPath: String) async -> Outcome<Void>
}

/// Ported from: lib/features/app_update/domain/repositories/auto_update_preference.dart
/// Whether the app looks for new versions, and downloads them, on its own. On by default.
public protocol AutoUpdatePreference: Sendable {
    func isEnabled() async -> Outcome<Bool>
    func setEnabled(_ enabled: Bool) async -> Outcome<Void>
}
