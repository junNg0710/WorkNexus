/// Ported from: lib/features/ticket_editor/domain/usecases/validate_ticket_draft.dart (`DraftField`)
/// A form field that must be filled in (or put right) before saving.
public enum DraftField: Hashable, Sendable {
    case title, openedBuilds, name, type, execution, product, deadline
}
