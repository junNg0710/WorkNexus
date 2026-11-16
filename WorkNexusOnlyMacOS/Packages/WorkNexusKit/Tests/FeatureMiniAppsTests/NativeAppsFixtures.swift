import CoreDomain
import CorePersistence
import Foundation
@testable import FeatureMiniApps

/// A scratch folder, deleted by the caller.
func nativeTempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("native_apps_test_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

/// Builds a minimal `.app` bundle (only its `Contents/Info.plist`: nothing here can be launched) and returns its path.
@discardableResult
func makeFixtureApp(in folder: URL, file: String, bundleId: String?, displayName: String? = nil, bundleName: String? = nil,
                    packageType: String? = "APPL", extra: [String: Any] = [:]) throws -> String {
    let bundle = folder.appendingPathComponent("\(file).app", isDirectory: true)
    let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    var plist: [String: Any] = extra
    if let bundleId { plist["CFBundleIdentifier"] = bundleId }
    if let displayName { plist["CFBundleDisplayName"] = displayName }
    if let bundleName { plist["CFBundleName"] = bundleName }
    if let packageType { plist["CFBundlePackageType"] = packageType }
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    return bundle.path
}

func native(_ id: String, bundle: String? = nil, path: String? = nil, position: Int = 0) -> NativeApp {
    NativeApp(id: id, name: id.capitalized, bundleId: bundle ?? "com.test.\(id)", path: path ?? "/Applications/\(id.capitalized).app", position: position)
}

/// A repository in memory, for the use cases.
final class FixtureNativeRepository: NativeAppRepository, @unchecked Sendable {
    var items: [NativeApp] = []
    var failing = false
    private(set) var order: [String] = []
    func watchAll() -> AsyncStream<[NativeApp]> { AsyncStream { $0.yield(self.items.sorted { $0.position < $1.position }) } }
    func save(_ app: NativeApp) async -> Outcome<Void> {
        if failing { return .failure(.storage("nope")) }
        items.removeAll { $0.id == app.id }; items.append(app); return .success(())
    }
    func saveOrder(_ ids: [String]) async -> Outcome<Void> { order = ids; return .success(()) }
    func delete(id: String) async -> Outcome<Void> { items.removeAll { $0.id == id }; return .success(()) }
}

/// An `AppLauncher` that opens nothing: it records what it was asked and lets a test send launch / quit events.
@MainActor
final class FakeLauncher: AppLauncher {
    var running: Set<String> = []
    var present: Set<String>?
    var launchResult: Outcome<Void> = .success(())
    private(set) var launched: [String] = []
    private(set) var revealed: [String] = []
    private var continuation: AsyncStream<RunningAppEvent>.Continuation?

    func runningBundleIds() -> Set<String> { running }
    func launch(path: String, bundleId: String) async -> Outcome<Void> { launched.append(bundleId); return launchResult }
    func reveal(path: String) { revealed.append(path) }
    func exists(path: String) -> Bool { present?.contains(path) ?? true }
    func events() -> AsyncStream<RunningAppEvent> { AsyncStream { self.continuation = $0 } }
    func send(_ event: RunningAppEvent) { continuation?.yield(event) }
}

struct FixtureInstalled: InstalledAppsSource {
    var apps: [AppBundleInfo]
    func installed() async -> [AppBundleInfo] { apps }
}

/// The model over an in-memory database, a fake launcher and the real plist reader.
@MainActor
struct NativeHarness {
    let model: NativeAppsModel
    let launcher = FakeLauncher()
    let dock = FakeDock()
    let offers = InMemoryBadgeOfferMemory()
    let repository: GRDBNativeAppRepository
    let dir = nativeTempDir()

    init(installed: [AppBundleInfo] = []) throws {
        let db = try AppDatabase.inMemory(registrars: [MiniAppsMigrations.registrar])
        repository = GRDBNativeAppRepository(database: db)
        let reader = PlistAppBundleReader()
        model = NativeAppsModel(repository: repository, add: AddNativeApp(repository, reader), remove: RemoveNativeApp(repository),
                                move: MoveNativeApp(repository), installed: FixtureInstalled(apps: installed), launcher: launcher, dock: dock, offerMemory: offers)
    }

    func settle(_ ok: @MainActor () -> Bool) async {
        for _ in 0..<300 where !ok() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// Saves apps and starts the model once it shows them.
    func seed(_ apps: [NativeApp]) async {
        for a in apps { _ = await repository.save(a) }
        model.start()
        await settle { model.apps.count == apps.count }
    }
}

/// The Dock's badges, as a test sets them.
@MainActor
final class FakeDock: DockBadgeSource {
    var isAllowed = true
    var asked = 0
    var byPath: [String: String] = [:]
    var opened = 0
    func requestAccess() { asked += 1 }
    func openSettings() { opened += 1 }
    func badges() -> [String: String] { isAllowed ? byPath : [:] }
}
