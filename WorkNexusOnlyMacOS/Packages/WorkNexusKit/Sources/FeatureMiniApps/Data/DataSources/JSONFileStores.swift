import Foundation

/// Ported from: lib/features/mini_apps/data/datasources/trusted_certificate_store.dart, cookie_import_store.dart
/// A small JSON file in the support folder. Throws on a file it cannot read or write; a damaged file reads as empty.
struct JSONListFile {
    let url: URL

    func read() throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        // A damaged file trusts nothing / forgets the imports; the user is asked again.
        guard let decoded = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return decoded.compactMap { $0 as? [String: Any] }
    }

    /// Replaces what is kept with `rows`; none removes the file.
    func write(_ rows: [[String: Any]]) throws {
        if rows.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: rows).write(to: url, options: .atomic)
    }
}

/// The trusted certificates, one JSON file.
struct TrustedCertificateStore {
    let file: JSONListFile

    func read() throws -> [TrustedCertificate] {
        try file.read().compactMap { item in
            guard let origin = item["origin"] as? String, let error = item["error"] as? String else { return nil }
            return TrustedCertificate(origin: origin, error: error)
        }
    }

    func write(_ items: [TrustedCertificate]) throws { try file.write(items.map { ["origin": $0.origin, "error": $0.error] }) }
}

/// The imported sites: where the cookies came from and their names, never their values. Same JSON shape as the Flutter build.
struct CookieImportStore {
    let file: JSONListFile
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    func read() throws -> [CookieImport] { try file.read().compactMap(Self.fromJSON) }
    func write(_ imports: [CookieImport]) throws { try file.write(imports.map(Self.toJSON)) }

    static func toJSON(_ i: CookieImport) -> [String: Any] {
        ["site": i.site, "browser": i.source.browser.rawValue, "profileId": i.source.profileId, "profileName": i.source.profileName,
         "importedAt": iso.string(from: i.importedAt),
         "keys": i.keys.map { ["host": $0.host, "path": $0.path, "name": $0.name] }]
    }

    static func fromJSON(_ json: [String: Any]) -> CookieImport? {
        guard let browser = (json["browser"] as? String).flatMap(CookieBrowser.init(rawValue:)),
              let at = (json["importedAt"] as? String).flatMap({ iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }),
              let site = json["site"] as? String, let profileId = json["profileId"] as? String,
              let profileName = json["profileName"] as? String, let keys = json["keys"] as? [Any] else { return nil }
        return CookieImport(site: site, source: CookieSource(browser: browser, profileId: profileId, profileName: profileName), importedAt: at,
                            keys: keys.compactMap { k in
                                guard let m = k as? [String: Any], let h = m["host"] as? String, let p = m["path"] as? String,
                                      let n = m["name"] as? String else { return nil }
                                return CookieKey(host: h, path: p, name: n)
                            })
    }
}
