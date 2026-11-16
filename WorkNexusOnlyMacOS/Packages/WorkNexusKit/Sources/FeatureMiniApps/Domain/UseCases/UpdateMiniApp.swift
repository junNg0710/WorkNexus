import CoreDomain
import Foundation

/// Ported from: lib/features/mini_apps/domain/usecases/update_mini_app.dart
/// Applies an edit to `app`: a new address, name and icon. A blank `name` becomes the site's host; an app left without an
/// icon gets its site's.
public struct UpdateMiniApp: Sendable {
    private let repository: MiniAppRepository
    private let refreshIcon: RefreshMiniAppIcon
    private let normalize = NormalizeMiniAppUrl()

    public init(_ repository: MiniAppRepository, _ refreshIcon: RefreshMiniAppIcon) {
        self.repository = repository; self.refreshIcon = refreshIcon
    }

    public func callAsFunction(app: MiniApp, url: String, name: String, iconPath: String?) async -> Outcome<MiniApp> {
        guard let uri = normalize(url) else { return .failure(.parse("Not a web address")) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = MiniApp(id: app.id, name: trimmed.isEmpty ? normalize.defaultName(uri) : trimmed, url: uri.absoluteString,
                              iconPath: iconPath,
                              // A new address starts from its own page.
                              lastUrl: uri.absoluteString == app.url ? app.lastUrl : nil, position: app.position)
        if case .failure(let f) = await repository.save(updated) { return .failure(f) }
        if iconPath == nil { let refresh = refreshIcon; Task { _ = await refresh(updated) } }
        return .success(updated)
    }
}
