import CoreDomain
import Foundation

/// New (no Dart counterpart): `WebLoginRepository` over the keychain — one generic-password item per origin and user, the
/// password as the item's secret and nothing else anywhere: not in the database, a file, the defaults or a log. The
/// never-save list (origins only) is a small JSON file.
public actor KeychainWebLoginRepository: WebLoginRepository {
    private let items: KeychainItemStore
    private let never: JSONListFile
    private static let readFailure = "Could not read the saved passwords"
    private static let writeFailure = "Could not change the saved passwords"

    init(items: KeychainItemStore, neverSaveFile: URL) {
        self.items = items; never = JSONListFile(url: neverSaveFile)
    }

    /// The item's account: the origin (which has no space in it), a space, the username.
    static func account(origin: String, username: String) -> String { "\(origin) \(username)" }

    static func summary(ofAccount account: String) -> WebLoginSummary? {
        guard let space = account.firstIndex(of: " ") else { return nil }
        let origin = String(account[..<space])
        guard webOrigin(ofAddress: origin) == origin else { return nil }
        return WebLoginSummary(origin: origin, username: String(account[account.index(after: space)...]))
    }

    /// What Keychain Access shows for the item.
    static func label(_ login: WebLoginSummary) -> String {
        login.username.isEmpty ? "WorkNexus: \(login.host)" : "WorkNexus: \(login.host) (\(login.username))"
    }

    public func summaries() async -> Outcome<[WebLoginSummary]> {
        do {
            return .success(try items.entries().compactMap { Self.summary(ofAccount: $0.account) }
                .sorted { ($0.host, $0.username) < ($1.host, $1.username) })
        } catch { return .failure(.storage(Self.readFailure)) }
    }

    public func logins(origin: String) async -> Outcome<[WebLogin]> {
        do {
            var found: [WebLogin] = []
            for entry in try items.entries() {
                guard let summary = Self.summary(ofAccount: entry.account), summary.origin == origin,
                      let data = try items.data(account: entry.account), let password = String(data: data, encoding: .utf8) else { continue }
                found.append(WebLogin(origin: origin, username: summary.username, password: password))
            }
            return .success(found.sorted { $0.username < $1.username })
        } catch { return .failure(.storage(Self.readFailure)) }
    }

    public func save(_ login: WebLogin) async -> Outcome<Void> {
        do {
            try items.set(account: Self.account(origin: login.origin, username: login.username), label: Self.label(login.summary),
                          data: Data(login.password.utf8))
            return .success(())
        } catch { return .failure(.storage(Self.writeFailure)) }
    }

    public func delete(origin: String, username: String) async -> Outcome<Void> {
        do { try items.remove(account: Self.account(origin: origin, username: username)); return .success(()) }
        catch { return .failure(.storage(Self.writeFailure)) }
    }

    public func deleteAll() async -> Outcome<Void> {
        do { try items.removeAll(); return .success(()) } catch { return .failure(.storage(Self.writeFailure)) }
    }

    public func neverSaveOrigins() async -> Outcome<[String]> {
        do { return .success(try never.read().compactMap { $0["origin"] as? String }.sorted()) }
        catch { return .failure(.storage(Self.readFailure)) }
    }

    public func setNeverSave(origin: String, _ on: Bool) async -> Outcome<Void> {
        do {
            var origins = Set(try never.read().compactMap { $0["origin"] as? String })
            if on { origins.insert(origin) } else { origins.remove(origin) }
            try never.write(origins.sorted().map { ["origin": $0] })
            return .success(())
        } catch { return .failure(.storage(Self.writeFailure)) }
    }
}
