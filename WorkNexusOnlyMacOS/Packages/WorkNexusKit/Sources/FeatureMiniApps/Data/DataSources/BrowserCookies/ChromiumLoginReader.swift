import Foundation
import GRDB

/// New (no Dart counterpart): the passwords a Chromium browser saved in a profile (`Login Data`, table `logins`), read from
/// a copy of the file. A password is encrypted like a cookie's value (`v10` / `v11`, AES-128-CBC under the browser's
/// "Safe Storage" key) but without the cookie's domain-hash prefix. Sites the user told the browser never to save for
/// (`blacklisted_by_user`) and rows without a password are skipped. Only read when the user asked to import passwords.
final class ChromiumLoginReader: @unchecked Sendable {
    /// Where the browser's key comes from: the cookie reader, which keeps it for the session.
    private let keys: ChromiumCookieReader

    init(keys: ChromiumCookieReader) { self.keys = keys }

    /// The profile's password databases: its own, and the one of the passwords kept in the browser's account.
    static func loginFiles(_ profile: String) -> [String] {
        ["\(profile)/Login Data", "\(profile)/Login Data For Account"].filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Every saved sign-in in the profile at `profilePath`. Throws `KeychainDeniedError` when the keychain refuses the key,
    /// and a no-permission error for a folder macOS keeps this app out of.
    func read(_ browser: CookieBrowser, profilePath: String) async throws -> [WebLogin] {
        let files = Self.loginFiles(profilePath)
        guard !files.isEmpty else {
            let parent = (profilePath as NSString).deletingLastPathComponent
            if !ChromiumCookieReader.canList(profilePath) || !ChromiumCookieReader.canList(parent) {
                throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: profilePath])
            }
            // A profile that never saved a password has no such file: nothing to import.
            return []
        }
        let crypto = try await keys.crypto(for: browser)
        return try await Task.detached { try files.flatMap { try Self.readFile($0, crypto) } }.value
    }

    static func readFile(_ file: String, _ crypto: ChromiumCookieCrypto) throws -> [WebLogin] {
        try readSQLiteSnapshot(file) { db in
            let rows = try Row.fetchAll(db, sql: "SELECT origin_url, username_value, password_value, blacklisted_by_user FROM logins")
            return rows.compactMap { row in
                guard (row["blacklisted_by_user"] as Int64?) != 1, let address = row["origin_url"] as String?,
                      let origin = webOrigin(ofAddress: address), let encrypted = row["password_value"] as Data?, !encrypted.isEmpty,
                      let password = crypto.decrypt(encrypted, hasDomainHash: false), !password.isEmpty else { return nil }
                return WebLogin(origin: origin, username: (row["username_value"] as String?) ?? "", password: password)
            }
        }
    }
}
