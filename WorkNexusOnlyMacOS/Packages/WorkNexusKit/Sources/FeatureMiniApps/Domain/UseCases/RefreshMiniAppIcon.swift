import CoreDomain

/// Ported from: lib/features/mini_apps/domain/usecases/refresh_mini_app_icon.dart
/// Gives `app` the icon of its site. Resolves to the app as kept; unchanged when the site has no icon.
public struct RefreshMiniAppIcon: Sendable {
    private let repository: MiniAppRepository
    public init(_ repository: MiniAppRepository) { self.repository = repository }

    public func callAsFunction(_ app: MiniApp) async -> Outcome<MiniApp> {
        switch await repository.fetchSiteIcon(id: app.id, pageUrl: app.url) {
        case .failure(let f): return .failure(f)
        case .success(nil): return .success(app)
        case .success(let path?):
            var updated = app; updated.iconPath = path
            switch await repository.save(updated) {
            case .success: return .success(updated)
            case .failure(let f): return .failure(f)
            }
        }
    }
}
