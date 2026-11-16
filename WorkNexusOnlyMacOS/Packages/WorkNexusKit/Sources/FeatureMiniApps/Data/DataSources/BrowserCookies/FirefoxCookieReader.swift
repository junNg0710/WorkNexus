import Foundation
import GRDB

struct FirefoxProfile: Equatable { var path: String; var name: String }

/// One `[ProfileN]` section of `profiles.ini`.
struct FirefoxIniProfile: Equatable { var name: String; var path: String; var relative: Bool }

/// Ported from: lib/features/mini_apps/data/datasources/browser_cookies/firefox_cookie_reader.dart
/// Firefox's cookies, kept unencrypted in each profile's `cookies.sqlite`.
struct FirefoxCookieReader: Sendable {
    private let root: String

    init(root: String? = nil) {
        self.root = root ?? "\(ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory())/Library/Application Support/Firefox"
    }

    /// The profiles listed in `profiles.ini` that have cookies.
    func profiles() -> [FirefoxProfile] {
        guard let text = try? String(contentsOfFile: "\(root)/profiles.ini", encoding: .utf8) else { return [] }
        return Self.parseProfilesIni(text).compactMap { section in
            let path = section.relative ? "\(root)/\(section.path)" : section.path
            return FileManager.default.fileExists(atPath: "\(path)/cookies.sqlite") ? FirefoxProfile(path: path, name: section.name) : nil
        }
    }

    func read(profilePath: String) async throws -> [BrowserCookie] {
        try await Task.detached {
            try readSQLiteSnapshot("\(profilePath)/cookies.sqlite") { db in
                try Row.fetchAll(db, sql: "SELECT name, value, host, path, expiry, isSecure, isHttpOnly, sameSite FROM moz_cookies").map { row in
                    let same: CookieSameSite
                    switch row["sameSite"] as Int64? { case 0: same = .none; case 1: same = .lax; case 2: same = .strict; default: same = .unspecified }
                    return BrowserCookie(name: row["name"], value: (row["value"] as String?) ?? "", domain: row["host"], path: (row["path"] as String?) ?? "/",
                                         expires: firefoxExpiry(row["expiry"] as Int64?), secure: (row["isSecure"] as Int64?) == 1,
                                         httpOnly: (row["isHttpOnly"] as Int64?) == 1, sameSite: same)
                }
            }
        }.value
    }

    /// The profiles `profiles.ini` lists.
    static func parseProfilesIni(_ text: String) -> [FirefoxIniProfile] {
        var found: [FirefoxIniProfile] = []
        var section: [String: String]?
        func flush() {
            guard let path = section?["Path"] else { return }
            found.append(FirefoxIniProfile(name: section?["Name"] ?? String(path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last ?? ""),
                                           path: path, relative: section?["IsRelative"] != "0"))
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                flush()
                section = line.hasPrefix("[Profile") ? [:] : nil
            } else if section != nil, let eq = line.firstIndex(of: "=") {
                section?[String(line[..<eq])] = String(line[line.index(after: eq)...])
            }
        }
        flush()
        return found
    }
}

/// Firefox wrote the expiry in seconds and, since version 136, writes it in milliseconds; a value past the year 5000 in
/// seconds can only be the latter. Zero or none is a session cookie.
func firefoxExpiry(_ value: Int64?) -> Date? {
    guard let value, value > 0 else { return nil }
    let ms = value > 100_000_000_000 ? value : value * 1000
    return Date(timeIntervalSince1970: Double(ms) / 1000)
}
