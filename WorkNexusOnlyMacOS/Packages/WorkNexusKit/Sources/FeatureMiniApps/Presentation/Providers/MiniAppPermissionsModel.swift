import CoreDomain
import Foundation
import Observation

/// Ported from: lib/features/mini_apps/presentation/providers/mini_app_providers.dart (miniAppPermissions / miniAppPermissionController)
/// What the user allowed or blocked for one mini app, live, in the order the kinds are listed; flip an answer or forget it so
/// the page is asked again.
@MainActor @Observable
final class MiniAppPermissionsModel {
    private(set) var grants: [MiniAppPermissionGrant] = []
    let miniAppId: String
    private let repository: MiniAppPermissionRepository

    init(miniAppId: String, repository: MiniAppPermissionRepository) { self.miniAppId = miniAppId; self.repository = repository }

    /// Follows the answers until cancelled (run it from a `.task`).
    func watch() async {
        for await list in repository.watch(miniAppId: miniAppId) { grants = list.sorted { $0.kind < $1.kind } }
    }

    /// Remembers `decision` for `kind`; false when it could not be kept.
    func remember(_ kind: MiniAppPermissionKind, _ decision: MiniAppPermissionDecision) async -> Bool {
        let result = await repository.save(MiniAppPermissionGrant(miniAppId: miniAppId, kind: kind, decision: decision))
        if case .success = result { return true }
        return false
    }

    /// Forgets the answer for `kind`; false when that failed.
    func forget(_ kind: MiniAppPermissionKind) async -> Bool {
        if case .success = await repository.clear(miniAppId: miniAppId, kind: kind) { return true }
        return false
    }
}
