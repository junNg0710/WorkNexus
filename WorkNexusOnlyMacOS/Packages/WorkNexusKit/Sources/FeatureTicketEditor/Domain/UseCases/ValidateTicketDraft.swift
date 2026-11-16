import CoreDomain

/// Ported from: lib/features/ticket_editor/domain/usecases/validate_ticket_draft.dart
/// The fields a bug needs before ZenTao takes it (its default required fields: title and the affected build).
public struct ValidateBugDraft: Sendable {
    public init() {}
    public func callAsFunction(_ draft: BugDraft) -> Set<DraftField> {
        var missing = Set<DraftField>()
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.insert(.title) }
        if draft.openedBuilds.isEmpty { missing.insert(.openedBuilds) }
        if draft.product == "0" || draft.product.isEmpty { missing.insert(.product) }
        return missing
    }
}

/// The fields a task needs before ZenTao takes it (name, type, execution), and a deadline ZenTao would refuse for
/// coming before the planned start.
public struct ValidateTaskDraft: Sendable {
    public init() {}
    public func callAsFunction(_ draft: TaskDraft) -> Set<DraftField> {
        var missing = Set<DraftField>()
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.insert(.name) }
        if draft.type.isEmpty { missing.insert(.type) }
        if draft.execution == "0" || draft.execution.isEmpty { missing.insert(.execution) }
        // Both are `yyyy-MM-dd`, so they compare as text.
        if !draft.estStarted.isEmpty, !draft.deadline.isEmpty, draft.deadline < draft.estStarted { missing.insert(.deadline) }
        return missing
    }
}
