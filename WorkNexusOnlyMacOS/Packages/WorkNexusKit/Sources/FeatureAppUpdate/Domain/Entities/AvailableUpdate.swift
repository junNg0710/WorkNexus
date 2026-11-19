/// Ported from: lib/features/app_update/domain/entities/available_update.dart
/// A stable release newer than the running build. `downloadUrl`/`sha256` are nil when the release carries no
/// (verifiable) build for this platform; the update then can only be fetched by hand from `releaseUrl`.
public struct AvailableUpdate: Sendable, Equatable, Identifiable {
    public var id: String { latestVersion }
    public var currentVersion: String
    public var latestVersion: String
    public var releaseUrl: String
    /// What changed, as GitHub Markdown; empty when the release has none.
    public var releaseNotes: String
    public var downloadUrl: String?
    public var sha256: String?

    public init(currentVersion: String, latestVersion: String, releaseUrl: String, releaseNotes: String = "",
                downloadUrl: String? = nil, sha256: String? = nil) {
        self.currentVersion = currentVersion; self.latestVersion = latestVersion; self.releaseUrl = releaseUrl
        self.releaseNotes = releaseNotes; self.downloadUrl = downloadUrl; self.sha256 = sha256
    }

    public var canInstallInApp: Bool { downloadUrl != nil && sha256 != nil }

    /// `v1.9.5` for the tag `v1.9.5+mac`: the version as the UI names it.
    public var latestTag: String { AppVersion(latestVersion)?.tag ?? latestVersion }
}
