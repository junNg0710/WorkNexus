import CoreDomain

/// Replaces lib/features/mini_apps/domain/usecases/move_mini_app.dart, which ordered the websites alone.
/// Moves the entry at index `from` of `order` (the rail's websites and Mac apps, in rail order) to index `to`, and keeps
/// the new order. Resolves to the reordered list, so the rail can show it before the database answers.
public struct MoveRailApp: Sendable {
    private let repository: RailOrderRepository
    public init(_ repository: RailOrderRepository) { self.repository = repository }

    public func callAsFunction(_ order: [RailAppRef], from: Int, to: Int) async -> Outcome<[RailAppRef]> {
        guard let moved = Self.reorder(order, from: from, to: to) else { return .success(order) }
        switch await repository.saveOrder(moved) {
        case .success: return .success(moved)
        case .failure(let f): return .failure(f)
        }
    }

    /// `order` with the entry at `from` taking the place at `to` and the rest shifting; nil when the move goes nowhere or
    /// is out of range.
    public static func reorder(_ order: [RailAppRef], from: Int, to: Int) -> [RailAppRef]? {
        guard from != to, order.indices.contains(from), order.indices.contains(to) else { return nil }
        var moved = order
        moved.insert(moved.remove(at: from), at: to)
        return moved
    }
}
