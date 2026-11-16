/// Ported from: lib/core/domain/value_objects/unified_status.dart
public enum UnifiedStatus: String, Codable, CaseIterable, Sendable, Hashable {
    case inbox, todo, inprogress, review, blocked, done

    public var order: Int { Self.allCases.firstIndex(of: self)! }
    public static var columns: [UnifiedStatus] { allCases.sorted { $0.order < $1.order } }
}
