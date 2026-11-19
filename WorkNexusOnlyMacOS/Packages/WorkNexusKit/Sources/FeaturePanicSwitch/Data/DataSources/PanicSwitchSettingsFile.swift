import Foundation

/// Ported from: lib/features/panic_switch/data/datasources/panic_switch_settings_store.dart
/// Keeps the panic switch settings as one JSON file in the support folder (the Flutter app keeps the same JSON as one value
/// of its key-value table), so they need no table or migration of their own.
struct PanicSwitchSettingsFile: Sendable {
    let url: URL

    /// The saved JSON, or nil when nothing was saved yet.
    func read() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
