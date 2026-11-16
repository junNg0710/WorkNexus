/// Ported from: lib/shared/board/domain/value_objects/saved_view.dart
/// Built-in saved views (the sidebar "Views" section). Predicates are applied in `FilterTickets`.
public enum SavedView: String, CaseIterable, Sendable, Hashable {
    case all, today, mine
    /// Mine in any role: assigned to me, or opened, resolved or finished by me (ZenTao "Related to me").
    case related
    case review, blocked

    public static func byId(_ id: String) -> SavedView? { SavedView(rawValue: id) }
}
