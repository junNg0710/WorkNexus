/// Ported from: lib/tools/zentao/presentation/providers/zentao_board_providers.dart (selection value types)
import CoreDomain
import CoreTools
import Foundation

/// The product whose bug board is open (Flutter `ZenTaoProductSelection`).
public struct ZentaoProductSelection: Equatable, Sendable {
    public var accountId: String
    public var productId: String
    public var productName: String
}

/// The execution whose task board is open (Flutter `ZenTaoExecutionSelection`).
public struct ZentaoExecutionSelection: Equatable, Sendable {
    public var accountId: String
    public var projectId: String
    public var executionId: String
    public var executionName: String
}

/// One module of a product / execution: its id and its path ("Livestream/Share").
public struct ZentaoModulePath: Hashable, Sendable {
    public var id: String
    public var path: String
    public init(id: String, path: String) { self.id = id; self.path = path }
}

/// A value that is loading, loaded or failed (Flutter `AsyncValue`).
public enum ZentaoLoad<T> {
    case loading
    case loaded(T)
    case failed(Failure)

    public var value: T? { if case .loaded(let v) = self { v } else { nil } }
    public var isLoading: Bool { if case .loading = self { true } else { false } }
    public var failure: Failure? { if case .failed(let f) = self { f } else { nil } }
}

/// A weak handle that closures running off the main actor (the paged fetchers) can capture.
final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
}

/// The section ids of the ZenTao tool.
public enum ZentaoSection {
    public static let tasks: SectionID = "zentao.tasks"
    public static let bugs: SectionID = "zentao.bugs"
    public static let docs: SectionID = "zentao.docs"
}
