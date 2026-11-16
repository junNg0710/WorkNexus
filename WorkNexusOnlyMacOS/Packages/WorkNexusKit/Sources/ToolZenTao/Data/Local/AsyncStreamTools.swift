/// Ported from: drift Stream.distinct usage in local_zentao_doc_repository.dart
import Foundation

extension AsyncStream where Element: Equatable & Sendable {
    /// Drops consecutive equal values (Dart `Stream.distinct`): an unchanged DB row does not re-emit.
    func removingDuplicates() -> AsyncStream<Element> {
        AsyncStream<Element> { continuation in
            let task = Task {
                var last: Element?
                var first = true
                for await value in self {
                    if first || last != value { continuation.yield(value) }
                    first = false
                    last = value
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
