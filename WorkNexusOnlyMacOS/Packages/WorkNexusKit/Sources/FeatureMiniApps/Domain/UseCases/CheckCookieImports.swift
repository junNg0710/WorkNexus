import CoreDomain

/// Ported from: lib/features/mini_apps/domain/usecases/check_cookie_imports.dart
/// The imported sites, each with how many of its sign-in cookies the web view no longer has: expired, signed out or
/// cleared. Such a site wants importing again.
public struct CheckCookieImports: Sendable {
    private let imports: CookieImportRepository
    private let webView: WebViewCookieRepository
    public init(_ imports: CookieImportRepository, _ webView: WebViewCookieRepository) { self.imports = imports; self.webView = webView }

    public func callAsFunction() async -> Outcome<[CookieImportState]> {
        let all: [CookieImport]
        switch await imports.all() {
        case .success(let v): all = v
        case .failure(let f): return .failure(f)
        }
        var states: [CookieImportState] = []
        for item in all {
            switch await webView.present(item.keys) {
            case .success(let present): states.append(CookieImportState(cookieImport: item, missing: item.keys.filter { !present.contains($0) }.count))
            case .failure(let f): return .failure(f)
            }
        }
        return .success(states)
    }
}
