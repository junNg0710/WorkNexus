import Foundation
import GRDB

/// A Chromium profile: its folder and the name the browser shows for it.
struct ChromiumProfile: Equatable { var path: String; var name: String }

/// The keychain did not give out a browser's cookie password: the user refused, or it is not there.
struct KeychainDeniedError: Error, Equatable { let service: String }

/// Result of running a short command (`security find-generic-password`).
struct CommandResult: Sendable { var status: Int32; var stdout: String }
typealias CommandRunner = @Sendable (_ executable: String, _ arguments: [String]) async -> CommandResult

func runCommand(_ executable: String, _ arguments: [String]) async -> CommandResult {
    await withCheckedContinuation { cont in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable.hasPrefix("/") ? executable : "/usr/bin/\(executable)")
        p.arguments = arguments
        let out = Pipe()
        p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { cont.resume(returning: CommandResult(status: -1, stdout: "")); return }
        DispatchQueue.global().async {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            cont.resume(returning: CommandResult(status: p.terminationStatus, stdout: String(decoding: data, as: UTF8.self)))
        }
    }
}

/// Ported from: lib/features/mini_apps/data/datasources/browser_cookies/chromium_cookie_reader.dart
/// The cookies of Chromium browsers on macOS. Reading the keychain password makes macOS ask the user once; the key is then
/// kept for the session.
final class ChromiumCookieReader: @unchecked Sendable {
    private struct Install { var dataDir: String; var keychainService: String }
    private let home: String
    private let run: CommandRunner
    private let keys = Locked<[CookieBrowser: ChromiumCookieCrypto]>([:])

    init(home: String? = nil, run: @escaping CommandRunner = { await runCommand($0, $1) }) {
        self.home = home ?? ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        self.run = run
    }

    private static func install(_ b: CookieBrowser) -> Install? {
        switch b {
        case .chrome: Install(dataDir: "Google/Chrome", keychainService: "Chrome Safe Storage")
        case .edge: Install(dataDir: "Microsoft Edge", keychainService: "Microsoft Edge Safe Storage")
        case .brave: Install(dataDir: "BraveSoftware/Brave-Browser", keychainService: "Brave Safe Storage")
        case .arc: Install(dataDir: "Arc/User Data", keychainService: "Arc Safe Storage")
        case .firefox, .safari: nil
        }
    }

    private func dataDir(_ b: CookieBrowser) -> String? {
        Self.install(b).map { "\(home)/Library/Application Support/\($0.dataDir)" }
    }

    /// `browser`'s profiles that have cookies, named as it names them.
    /// A browser whose data folder macOS will not let this app open (Privacy: Full Disk Access) still gets its main profile,
    /// so the user can pick it and be told what to switch on, instead of the browser silently missing from the list.
    func profiles(_ browser: CookieBrowser) -> [ChromiumProfile] {
        guard let dir = dataDir(browser), FileManager.default.fileExists(atPath: dir) else { return [] }
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
            return [ChromiumProfile(path: "\(dir)/Default", name: "Default")]
        }
        let names = Self.profileNames(dir)
        let found = entries.compactMap { entry -> ChromiumProfile? in
            let path = "\(dir)/\(entry)"
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
            guard Self.cookieFile(path) != nil || (Self.isProfileFolder(entry) && !Self.canList(path)) else { return nil }
            return ChromiumProfile(path: path, name: names[entry] ?? entry)
        }.sorted { $0.name < $1.name }
        return found
    }

    /// `Default` or `Profile 3`.
    static func isProfileFolder(_ name: String) -> Bool { name == "Default" || name.hasPrefix("Profile ") }

    static func canList(_ path: String) -> Bool { (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil }

    /// The names `Local State` gives each profile folder.
    static func profileNames(_ dataDir: String) -> [String: String] {
        guard let data = FileManager.default.contents(atPath: "\(dataDir)/Local State"),
              let state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cache = (state["profile"] as? [String: Any])?["info_cache"] as? [String: Any] else { return [:] }
        return cache.compactMapValues { ($0 as? [String: Any])?["name"] as? String }
    }

    /// The profile's cookie database: newer versions keep it under `Network`.
    static func cookieFile(_ profile: String) -> String? {
        ["\(profile)/Network/Cookies", "\(profile)/Cookies"].first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Every cookie in the profile at `profilePath`. Throws `KeychainDeniedError` when the keychain refuses the password.
    func read(_ browser: CookieBrowser, profilePath: String) async throws -> [BrowserCookie] {
        guard let file = Self.cookieFile(profilePath) else {
            // A folder macOS keeps this app out of is "no permission", not "no such file": the user can fix that.
            let parent = (profilePath as NSString).deletingLastPathComponent
            if FileManager.default.fileExists(atPath: profilePath), !Self.canList(profilePath) || !Self.canList(parent) {
                throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: profilePath])
            }
            if !Self.canList(parent) { throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: profilePath]) }
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: profilePath])
        }
        let cached = keys.withLock { $0[browser] }
        let crypto: ChromiumCookieCrypto
        if let cached { crypto = cached } else { crypto = try await keyFor(browser); keys.withLock { $0[browser] = crypto } }
        // Decrypting thousands of values is too slow for the main actor.
        return try await Task.detached { try Self.readFile(file, crypto) }.value
    }

    static func readFile(_ file: String, _ crypto: ChromiumCookieCrypto) throws -> [BrowserCookie] {
        try readSQLiteSnapshot(file) { db in
            let version = try Row.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'version'")
            let hasDomainHash = (Int(version?["value"] as String? ?? "") ?? Int((version?["value"] as Int64?) ?? 0)) >= 24
            let rows = try Row.fetchAll(db, sql: "SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite FROM cookies")
            return rows.compactMap { row in
                guard let value = value(plain: row["value"], encrypted: row["encrypted_value"], crypto, hasDomainHash) else { return nil }
                let same: CookieSameSite
                switch row["samesite"] as Int64? { case 0: same = .none; case 1: same = .lax; case 2: same = .strict; default: same = .unspecified }
                return BrowserCookie(name: row["name"], value: value, domain: row["host_key"], path: (row["path"] as String?) ?? "/",
                                     expires: chromiumExpiry(row["expires_utc"] as Int64?), secure: (row["is_secure"] as Int64?) == 1,
                                     httpOnly: (row["is_httponly"] as Int64?) == 1, sameSite: same)
            }
        }
    }

    private static func value(plain: String?, encrypted: Data?, _ crypto: ChromiumCookieCrypto, _ hasDomainHash: Bool) -> String? {
        if let plain, !plain.isEmpty { return plain }
        guard let encrypted, !encrypted.isEmpty else { return nil }
        return crypto.decrypt(encrypted, hasDomainHash: hasDomainHash)
    }

    private func keyFor(_ browser: CookieBrowser) async throws -> ChromiumCookieCrypto {
        guard let service = Self.install(browser)?.keychainService else { throw CocoaError(.fileReadUnknown) }
        let result = await run("security", ["find-generic-password", "-w", "-s", service])
        guard result.status == 0 else { throw KeychainDeniedError(service: service) }
        return ChromiumCookieCrypto(password: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Chromium counts microseconds from 1601; zero is a session cookie.
func chromiumExpiry(_ value: Int64?) -> Date? {
    guard let value, value > 0 else { return nil }
    let from1601To1970: Int64 = 11_644_473_600_000_000
    return Date(timeIntervalSince1970: Double(value - from1601To1970) / 1_000_000)
}
