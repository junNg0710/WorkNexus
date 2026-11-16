import CoreDomain

/// Ported from: lib/features/mini_apps/domain/usecases/move_mini_app.dart
/// Moves the app at index `from` of `apps` (in rail order) to index `to`, and keeps the new order. Resolves to the
/// reordered list, so the rail can show it before the database answers.
public struct MoveMiniApp: Sendable {
    private let repository: MiniAppRepository
    public init(_ repository: MiniAppRepository) { self.repository = repository }

    public func callAsFunction(_ apps: [MiniApp], from: Int, to: Int) async -> Outcome<[MiniApp]> {
        guard let moved = Self.reorder(apps, from: from, to: to) else { return .success(apps) }
        switch await repository.saveOrder(moved.map(\.id)) {
        case .success: return .success(moved)
        case .failure(let f): return .failure(f)
        }
    }

    /// `apps` with the one at `from` moved to `to` and positions renumbered; nil when the move goes nowhere or is out of range.
    public static func reorder(_ apps: [MiniApp], from: Int, to: Int) -> [MiniApp]? {
        let inRange = from >= 0 && to >= 0 && from < apps.count
        if from == to || !inRange || to >= apps.count { return nil }
        var moved = apps
        moved.insert(moved.remove(at: from), at: to)
        return moved.enumerated().map { i, a in var a = a; a.position = i; return a }
    }
}
