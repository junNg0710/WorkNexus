import CoreDomain

/// New feature, no Dart counterpart. The Mac apps the user put on the rail, kept on this device.
public protocol NativeAppRepository: Sendable {
    /// Every Mac app in rail order, live.
    func watchAll() -> AsyncStream<[NativeApp]>
    /// Keeps `app`, replacing the one with its id.
    func save(_ app: NativeApp) async -> Outcome<Void>
    /// Puts the apps in the order of `ids` on the rail, first to last. Touches nothing but their positions.
    func saveOrder(_ ids: [String]) async -> Outcome<Void>
    func delete(id: String) async -> Outcome<Void>
}

/// Reads what an `.app` bundle says about itself.
public protocol AppBundleReader: Sendable {
    /// The bundle's name and identifier; a failure when `path` is not a Mac app.
    func read(path: String) -> Outcome<AppBundleInfo>
}

/// The apps installed on this Mac, for the "Add Mac app" list.
public protocol InstalledAppsSource: Sendable {
    /// Windowed apps, by name, one per bundle identifier.
    func installed() async -> [AppBundleInfo]
}
