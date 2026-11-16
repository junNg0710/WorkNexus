import CoreDomain
import Foundation

/// Ported from: lib/features/connections/presentation/connection_controllers.dart (`_slug`, `_initials`, `_pickColor`,
/// the account / workspace id schemes) + lib/core/util/content_hash.dart (`intHash`).
/// The ids are stable across installs: `zt-{slug(username)}-{hex(intHash(baseUrl))}` etc. They key the account's
/// secret (`secret:{accountId}`) and its synced rows, so the scheme must not drift from the Flutter app.
public enum ConnectionIdentity {
    /// Stable non-negative 31-bit hash of a string (h*31+c over UTF-16 code units).
    public static func intHash(_ s: String) -> Int {
        var h = 0
        for u in s.utf16 { h = ((h &* 31) &+ Int(u)) & 0x7fff_ffff }
        return h
    }

    /// Lower-case, runs of anything but `a-z0-9` become one `-`, no leading / trailing `-`.
    public static func slug(_ s: String) -> String {
        var out = "", pendingDash = false
        for ch in s.lowercased() {
            if let a = ch.asciiValue, (a >= 97 && a <= 122) || (a >= 48 && a <= 57) {
                if pendingDash, !out.isEmpty { out.append("-") }
                pendingDash = false
                out.append(ch)
            } else {
                pendingDash = true
            }
        }
        return out
    }

    /// `intHash(s).toRadixString(16)`.
    public static func hex(_ s: String) -> String { String(intHash(s), radix: 16) }

    private static func prefix(_ p: ProviderType) -> String {
        switch p { case .zentao: "zt"; case .github: "gh"; case .gitlab: "gl"; case .jira: "jr" }
    }

    /// `zt-{slug}-{hash(url)}` (ZenTao hashes the *resolved* web root; GitHub / GitLab the typed URL, as typed).
    public static func accountId(provider: ProviderType, username: String, baseUrl: String) -> String {
        "\(prefix(provider))-\(slug(username))-\(hex(baseUrl))"
    }

    /// `ws-{slug(name)}-{hash(name)}` for a workspace created while connecting.
    public static func workspaceId(name: String) -> String { "ws-\(slug(name))-\(hex(name))" }

    /// Up-to-2-letter badge from a workspace name ("Company C" → "CC", "Erp" → "E").
    public static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = words.first else { return "?" }
        if words.count == 1 { return String(first.prefix(1)).uppercased() }
        return (String(first.prefix(1)) + String(words[1].prefix(1))).uppercased()
    }

    public static let palette: [Int] = [0xFF16A99C, 0xFFCF8A3A, 0xFF8F63D6, 0xFF3B82F6, 0xFFE05561, 0xFF2F8A52]

    public static func pickColor(_ name: String) -> Int { palette[intHash(name) % palette.count] }

    /// The workspace a connect dialog starts on: the only one when there is exactly one. With several the user
    /// must pick explicitly; with none the dialog hides the picker and connecting creates a default workspace.
    public static func initialWorkspaceId(_ workspaces: [Workspace]) -> String? {
        workspaces.count == 1 ? workspaces[0].id : nil
    }
}
