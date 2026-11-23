import CoreDomain
import Foundation

/// New feature, no Dart counterpart. Puts the Mac app at `path` (an `.app` bundle) at the end of the rail (after the websites too, when `order` is given), named and identified by
/// its `Info.plist`. An app already there (same bundle identifier) is not added twice: it is returned as it is, with its path and
/// name brought up to date when it moved, which is also how a missing app is located again. A path that is not a Mac app fails.
public struct AddNativeApp: Sendable {
    private let repository: NativeAppRepository
    private let reader: AppBundleReader
    private let order: RailOrderRepository?
    private let newId: @Sendable () -> String

    public init(_ repository: NativeAppRepository, _ reader: AppBundleReader, order: RailOrderRepository? = nil,
                newId: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }) {
        self.repository = repository; self.reader = reader; self.order = order; self.newId = newId
    }

    public func callAsFunction(path: String, existing: [NativeApp]) async -> Outcome<NativeApp> {
        let info: AppBundleInfo
        switch reader.read(path: path) {
        case .success(let read): info = read
        case .failure(let failure): return .failure(failure)
        }
        var app: NativeApp
        if let kept = existing.first(where: { $0.bundleId == info.bundleId }) {
            guard kept.path != info.path || kept.name != info.name else { return .success(kept) }
            app = kept; app.path = info.path; app.name = info.name
        } else {
            var next = (existing.map(\.position).max() ?? -1) + 1
            if let order, case .success(let end) = await order.nextPosition() { next = end }
            app = NativeApp(id: newId(), name: info.name, bundleId: info.bundleId, path: info.path, position: next)
        }
        if case .failure(let failure) = await repository.save(app) { return .failure(failure) }
        return .success(app)
    }
}
