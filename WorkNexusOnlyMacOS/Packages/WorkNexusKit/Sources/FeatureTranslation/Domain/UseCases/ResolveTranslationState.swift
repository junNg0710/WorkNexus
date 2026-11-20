/// Ported from: lib/features/translation/domain/usecases/resolve_translation_state.dart
/// Pure state-machine resolver for a ticket's translation:
/// loading → a request is in flight; no record → none (or error); record with matching hash → done; else outdated.
/// A record still in the source's CJK script for a non-CJK language is no translation: it counts as none, so it is asked
/// for again instead of being shown as translated.
public struct ResolveTranslationState: Sendable {
    public init() {}

    public func callAsFunction(currentSourceHash: String, record: TranslationRecord?, loading: Bool = false,
                               hasError: Bool = false) -> TranslationState {
        if loading { return .loading }
        guard let record, !IsUntranslated()(record) else { return hasError ? .error : .none }
        return record.sourceHash == currentSourceHash ? .done : .outdated
    }
}
