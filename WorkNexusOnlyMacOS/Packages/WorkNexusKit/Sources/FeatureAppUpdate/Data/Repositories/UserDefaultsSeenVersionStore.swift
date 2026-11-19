import CoreDomain
import Foundation

/// Ported from: lib/features/app_update/data/repositories/local_seen_version_store.dart
/// `SeenVersionStore` in the app's user defaults (the Flutter app keeps it in `app_settings_kv`): it survives the swap of
/// the `.app` bundle an update does, so the first launch of the new build finds the version that ran before.
public final class UserDefaultsSeenVersionStore: SeenVersionStore, @unchecked Sendable {
    public static let key = "app_update.last_seen_version"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func lastSeen() async -> Outcome<String?> { .success(defaults.string(forKey: Self.key)) }

    public func setLastSeen(_ version: String) async -> Outcome<Void> {
        defaults.set(version, forKey: Self.key)
        return .success(())
    }
}
