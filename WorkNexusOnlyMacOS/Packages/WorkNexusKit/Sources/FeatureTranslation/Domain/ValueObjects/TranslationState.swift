/// Ported from: lib/core/domain/value_objects/translation_state.dart
/// Lifecycle of a ticket's translation cache entry.
public enum TranslationState: Sendable, Equatable {
    case none       // never translated
    case loading    // a translation request is in flight
    case done       // cached translation matches the current source content hash
    case outdated   // a cached translation exists but the source changed since
    case error      // the last attempt failed
}
