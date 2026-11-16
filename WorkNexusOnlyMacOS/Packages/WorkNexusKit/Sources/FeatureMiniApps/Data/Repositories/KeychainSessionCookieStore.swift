import CoreDomain
import Foundation

/// New (no Dart counterpart): the session cookies kept between runs, as JSON in ONE keychain item — they are sign-ins, so
/// they are kept where the passwords are, not in a file.
public actor KeychainSessionCookieStore: SessionCookieStore {
    static let account = "session-cookies"
    private static let label = "WorkNexus: mini app sessions"
    private let items: KeychainItemStore

    init(items: KeychainItemStore) { self.items = items }

    public func load() async -> Outcome<[BrowserCookie]> {
        do {
            guard let data = try items.data(account: Self.account) else { return .success([]) }
            // A damaged item keeps nothing: the user signs in again.
            guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return .success([]) }
            return .success(rows.compactMap(Self.cookie))
        } catch { return .failure(.storage("Could not read the kept sessions")) }
    }

    public func save(_ cookies: [BrowserCookie]) async -> Outcome<Void> {
        do {
            if cookies.isEmpty { try items.remove(account: Self.account); return .success(()) }
            try items.set(account: Self.account, label: Self.label, data: try JSONSerialization.data(withJSONObject: cookies.map(Self.json)))
            return .success(())
        } catch { return .failure(.storage("Could not keep the sessions")) }
    }

    static func json(_ c: BrowserCookie) -> [String: Any] {
        ["name": c.name, "value": c.value, "domain": c.domain, "path": c.path, "secure": c.secure, "httpOnly": c.httpOnly,
         "sameSite": String(describing: c.sameSite)]
    }

    static func cookie(_ row: [String: Any]) -> BrowserCookie? {
        guard let name = row["name"] as? String, let value = row["value"] as? String, let domain = row["domain"] as? String else { return nil }
        let same: CookieSameSite
        switch row["sameSite"] as? String { case "lax": same = .lax; case "strict": same = .strict; case "none": same = .none; default: same = .unspecified }
        return BrowserCookie(name: name, value: value, domain: domain, path: row["path"] as? String ?? "/", expires: nil,
                             secure: row["secure"] as? Bool ?? false, httpOnly: row["httpOnly"] as? Bool ?? false, sameSite: same)
    }
}
