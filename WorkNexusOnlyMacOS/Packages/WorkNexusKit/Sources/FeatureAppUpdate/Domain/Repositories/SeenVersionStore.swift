import CoreDomain

/// Ported from: lib/features/app_update/domain/repositories/seen_version_store.dart
/// The version this computer last ran, to tell after an update that a new one is running.
public protocol SeenVersionStore: Sendable {
    /// Nil before the first launch that kept one.
    func lastSeen() async -> Outcome<String?>
    func setLastSeen(_ version: String) async -> Outcome<Void>
}
