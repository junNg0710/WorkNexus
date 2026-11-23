import CoreDomain

/// New feature, no Dart counterpart. The Mac apps the user put on the rail, kept on this device.
public protocol NativeAppRepository: Sendable {
    /// Every Mac app in rail order, live. The order itself is `RailOrderRepository`'s: the websites share it.
    func watchAll() -> AsyncStream<[NativeApp]>
    /// Keeps `app`, replacing the one with its id.
    func save(_ app: NativeApp) async -> Outcome<Void>
    func delete(id: String) async -> Outcome<Void>
    /// Keeps a copy of the image at `sourcePath` as app `id`'s rail icon; the copy's path.
    func importIcon(id: String, sourcePath: String) async -> Outcome<String>
    /// Forgets app `id`'s own icon file (it shows the app's icon again).
    func deleteIcon(id: String) async
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
