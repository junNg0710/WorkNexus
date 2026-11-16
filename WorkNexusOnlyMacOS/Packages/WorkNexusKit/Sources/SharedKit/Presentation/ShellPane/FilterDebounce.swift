import Foundation

/// Ported from: lib/shared/shell_pane/scope_filter_field.dart (`_onQueryChanged`)
/// Debounces a text filter: a non-empty query is applied after `delay` of quiet (a newer one replaces it), an empty
/// one is applied at once so clearing the field never lags.
@MainActor
public final class FilterDebounce {
    nonisolated public static let defaultDelay: Duration = .milliseconds(150)
    private var task: Task<Void, Never>?
    public init() {}

    public func submit(_ query: String, delay: Duration = FilterDebounce.defaultDelay, apply: @escaping @MainActor (String) -> Void) {
        task?.cancel()
        if query.isEmpty { task = nil; apply(""); return }
        task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            if !Task.isCancelled { apply(query) }
        }
    }

    public func cancel() { task?.cancel(); task = nil }
}
