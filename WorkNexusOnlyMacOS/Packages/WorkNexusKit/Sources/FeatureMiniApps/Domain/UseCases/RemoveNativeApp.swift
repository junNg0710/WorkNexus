import CoreDomain

/// New feature, no Dart counterpart. Takes the Mac app `id` off the rail; the app itself is not touched.
public struct RemoveNativeApp: Sendable {
    private let repository: NativeAppRepository
    public init(_ repository: NativeAppRepository) { self.repository = repository }

    public func callAsFunction(id: String) async -> Outcome<Void> {
        let removed = await repository.delete(id: id)
        if case .success = removed { await repository.deleteIcon(id: id) }
        return removed
    }
}
