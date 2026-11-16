import CoreDomain

/// New feature, no Dart counterpart (same shape as `MoveMiniApp`). Moves the Mac app at index `from` of `apps` (in rail order) to
/// index `to`, and keeps the new order. Resolves to the reordered list, so the rail can show it before the database answers.
public struct MoveNativeApp: Sendable {
    private let repository: NativeAppRepository
    public init(_ repository: NativeAppRepository) { self.repository = repository }

    public func callAsFunction(_ apps: [NativeApp], from: Int, to: Int) async -> Outcome<[NativeApp]> {
        guard let moved = Self.reorder(apps, from: from, to: to) else { return .success(apps) }
        switch await repository.saveOrder(moved.map(\.id)) {
        case .success: return .success(moved)
        case .failure(let f): return .failure(f)
        }
    }

    /// `apps` with the one at `from` moved to `to` and positions renumbered; nil when the move goes nowhere or is out of range.
    public static func reorder(_ apps: [NativeApp], from: Int, to: Int) -> [NativeApp]? {
        guard from != to, apps.indices.contains(from), apps.indices.contains(to) else { return nil }
        var moved = apps
        moved.insert(moved.remove(at: from), at: to)
        return moved.enumerated().map { i, a in var a = a; a.position = i; return a }
    }
}
