import CoreDomain
import Foundation

/// Ported from: lib/features/mini_apps/domain/usecases/add_mini_app.dart
/// Adds the web page at `url` to the end of the rail. A blank `name` becomes the site's host. The site's icon is fetched
/// afterwards, without making the caller wait for it: it shows up when it arrives.
public struct AddMiniApp: Sendable {
    private let repository: MiniAppRepository
    private let refreshIcon: RefreshMiniAppIcon
    private let normalize = NormalizeMiniAppUrl()
    private let newId: @Sendable () -> String

    public init(_ repository: MiniAppRepository, _ refreshIcon: RefreshMiniAppIcon,
                newId: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }) {
        self.repository = repository; self.refreshIcon = refreshIcon; self.newId = newId
    }

    public func callAsFunction(url: String, name: String = "", existing: [MiniApp]) async -> Outcome<MiniApp> {
        guard let uri = normalize(url) else { return .failure(.parse("Not a web address")) }
        let next = (existing.map(\.position).max() ?? -1) + 1
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = MiniApp(id: newId(), name: trimmed.isEmpty ? normalize.defaultName(uri) : trimmed, url: uri.absoluteString, position: next)
        if case .failure(let f) = await repository.save(app) { return .failure(f) }
        let refresh = refreshIcon
        Task { _ = await refresh(app) }
        return .success(app)
    }
}
