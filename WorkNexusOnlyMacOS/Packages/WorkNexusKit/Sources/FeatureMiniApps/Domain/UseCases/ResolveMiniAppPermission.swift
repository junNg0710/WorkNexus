/// Ported from: lib/features/mini_apps/domain/usecases/resolve_mini_app_permission.dart
/// What to do with a page's request for `kinds`: the remembered answer when every kind has one (allowed only if all are),
/// else nil — ask the user. A storage failure also asks: better a prompt than a silent grant.
public struct ResolveMiniAppPermission: Sendable {
    private let repository: MiniAppPermissionRepository
    public init(_ repository: MiniAppPermissionRepository) { self.repository = repository }

    public func callAsFunction(_ miniAppId: String, _ kinds: some Sequence<MiniAppPermissionKind>) async -> MiniAppPermissionDecision? {
        var allowed = true
        for kind in Set(kinds) {
            guard case .success(let d?) = await repository.decision(miniAppId: miniAppId, kind: kind) else { return nil }
            if d == .block { allowed = false }
        }
        return allowed ? .allow : .block
    }
}
