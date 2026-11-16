import Foundation

/// Public entry point of FeatureAppUpdate; the composition root calls `makeModel` once and keeps it alive
/// (the hourly check and a download in progress must outlive whichever view is showing).
public enum AppUpdateFeature {
    public static let name = "FeatureAppUpdate"

    /// - Parameters:
    ///   - currentVersion: `CFBundleShortVersionString`.
    ///   - quit: how the app terminates once the swap helper is running (default `exit(0)`; the app can pass `NSApp.terminate`).
    @MainActor
    public static func makeModel(config: AppUpdateConfig = AppUpdateConfig(),
                                 currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
                                 preference: AutoUpdatePreference = MarkerFileAutoUpdatePreference.inApplicationSupport(),
                                 session: URLSession = .shared,
                                 quit: @escaping @Sendable () -> Void = { exit(0) }) -> UpdateModel {
        let repo = GitHubUpdateRepository(
            releases: GitHubReleaseDataSource(config: config, session: session),
            installer: MacOSUpdateInstaller(assetName: config.macAssetName),
            config: config, currentVersion: currentVersion, quit: quit)
        return UpdateModel(checkForUpdate: CheckForUpdate(repo), downloadUpdate: DownloadUpdate(repo), installUpdate: InstallUpdate(repo),
                           autoUpdateEnabled: { (await preference.isEnabled()).value ?? true })
    }

    /// The automatic-update switch behind the settings card.
    public static func autoUpdatePreference() -> AutoUpdatePreference { MarkerFileAutoUpdatePreference.inApplicationSupport() }
}
