/// Ported from: lib/core/domain/value_objects/priority.dart
public enum Priority: String, Codable, CaseIterable, Sendable, Hashable {
    case urgent, high, medium, low

    public var level: Int { Self.allCases.firstIndex(of: self)! }
    public static func fromLevel(_ level: Int) -> Priority { allCases[min(max(level, 0), 3)] }
}
