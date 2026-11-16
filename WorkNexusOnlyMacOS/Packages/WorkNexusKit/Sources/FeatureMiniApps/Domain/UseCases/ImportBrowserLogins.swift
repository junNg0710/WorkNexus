import CoreDomain
import Foundation

/// New (no Dart counterpart): brings the passwords a browser saved for the chosen `sites` — and for those sites only — into
/// the mini apps' saved sign-ins. Answers how many went in. A sign-in already saved for the same site and user is updated.
/// Nothing is read unless the user asked for it in the import dialog.
public struct ImportBrowserLogins: Sendable {
    private let browsers: BrowserLoginRepository
    private let save: SaveWebLogin

    public init(_ browsers: BrowserLoginRepository, _ logins: WebLoginRepository) {
        self.browsers = browsers; save = SaveWebLogin(logins)
    }

    public func supports(_ browser: CookieBrowser) -> Bool { browsers.supports(browser) }

    public func callAsFunction(_ source: CookieSource, sites: Set<String>) async -> Outcome<Int> {
        guard browsers.supports(source.browser) else { return .success(0) }
        let found: [WebLogin]
        switch await browsers.read(source) {
        case .success(let all): found = all
        case .failure(let f): return .failure(f)
        }
        var imported = 0
        for login in Self.chosen(found, sites: sites) {
            if case .success = await save(login) { imported += 1 }
        }
        return .success(imported)
    }

    /// The sign-ins of `all` that belong to one of `sites` (the registrable domains the user picked): each once per origin
    /// and user, the later row winning, without the ones that have no password.
    static func chosen(_ all: [WebLogin], sites: Set<String>) -> [WebLogin] {
        var byKey: [WebLoginSummary: WebLogin] = [:], order: [WebLoginSummary] = []
        for login in all where !login.password.isEmpty {
            guard let origin = webOrigin(ofAddress: login.origin), sites.contains(cookieSite(of: webOriginHostName(origin))) else { continue }
            let kept = WebLogin(origin: origin, username: login.username, password: login.password)
            if byKey.updateValue(kept, forKey: kept.summary) == nil { order.append(kept.summary) }
        }
        return order.compactMap { byKey[$0] }
    }
}
