import Foundation

/// Ported from: lib/core/config/app_config.dart (identity bits) + path_provider's getApplicationSupportDirectory.
public enum AppIdentity {
    /// Product name shown in notifications and window titles.
    public static var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "WorkNexus"
    }
    public static var bundleId: String { Bundle.main.bundleIdentifier ?? "com.worknexus.macos" }
}

public enum PlatformPaths {
    /// `~/Library/Application Support/<bundle id>` (created on demand); same folder `AppDatabase.open` uses.
    public static func applicationSupport(bundleId: String = AppIdentity.bundleId) -> URL {
        // `WN_SUPPORT_DIR` redirects every per-user file (demo / UI-test runs never touch the real Application Support).
        if let override = ProcessInfo.processInfo.environment["WN_SUPPORT_DIR"], !override.isEmpty {
            let dir = URL(fileURLWithPath: override, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(bundleId, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
