/// Ported from: lib/features/mini_apps/domain/entities/mini_app_permission.dart
/// What a page may ask to use. Kept apart from any web view's own list so the choices stay stable when the web view changes.
/// Raw values are the Dart enum names (they are what the `miniAppPermissions.kind` column stores).
public enum MiniAppPermissionKind: String, Sendable, CaseIterable, Comparable {
    case notifications, clipboard, autoplay, multipleDownloads, localFonts, camera, microphone, location, other

    private var order: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (a: Self, b: Self) -> Bool { a.order < b.order }
}

/// The user's answer to a request.
public enum MiniAppPermissionDecision: Sendable, Equatable { case allow, block }

/// A remembered answer: app `miniAppId` may (`allow`) or may not (`block`) use `kind`. Without one for a kind, the user is asked.
public struct MiniAppPermissionGrant: Sendable, Equatable, Hashable {
    public var miniAppId: String
    public var kind: MiniAppPermissionKind
    public var decision: MiniAppPermissionDecision
    public init(miniAppId: String, kind: MiniAppPermissionKind, decision: MiniAppPermissionDecision) {
        self.miniAppId = miniAppId; self.kind = kind; self.decision = decision
    }
}
