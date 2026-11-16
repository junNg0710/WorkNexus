import Foundation

/// Ported from: lib/features/translation/data/datasources/opencode_auth_file.dart
/// Raw access to OpenCode's credential file (`auth.json`) — the file `opencode auth login` writes. Infrastructure
/// detail, confined to `Data/` (rule 3.4).
public struct OpenCodeAuthFile: Sendable {
    private let pathOverride: String?
    private let environment: [String: String]
    private static let fileName = "auth.json"

    /// - Parameter path: explicit file path, for tests and unusual installs. nil ⇒ the candidates below.
    public init(path: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) {
        pathOverride = path; self.environment = environment
    }

    /// The file OpenCode is actually using: the first candidate that exists, else the preferred location so a first
    /// save creates it where the CLI looks.
    public func resolve() -> URL {
        if let o = pathOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !o.isEmpty { return URL(fileURLWithPath: o) }
        let candidates = self.candidates()
        let hit = candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[0]
        return URL(fileURLWithPath: hit)
    }

    /// `$XDG_DATA_HOME/opencode/auth.json`, then `~/.local/share/opencode/auth.json` (the order OpenCode resolves them).
    private func candidates() -> [String] {
        let home = environment["HOME"] ?? NSHomeDirectory()
        var list: [String] = []
        if let xdg = environment["XDG_DATA_HOME"], !xdg.isEmpty { list.append("\(xdg)/opencode/\(Self.fileName)") }
        list.append("\(home)/.local/share/opencode/\(Self.fileName)")
        return list
    }

    /// Every entry keyed by provider id. A missing or empty file reads as `[:]` so a first save is an ordinary write.
    /// Throws on malformed JSON (callers must not overwrite what they can't parse).
    public func read() throws -> [String: Any] {
        let file = resolve()
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        let data = try Data(contentsOf: file)
        if String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Replaces the file's contents with `entries`. Written to a sibling temp file and renamed, so an interrupted write
    /// can't truncate the credentials OpenCode depends on, and `chmod 0600` because the file holds secrets.
    public func write(_ entries: [String: Any]) throws {
        let file = resolve()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = URL(fileURLWithPath: file.path + ".worknexus.tmp")
        let data = try JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys])
        try? FileManager.default.removeItem(at: temp)
        // Created 0600 from the start: the secrets are never world-readable, not even briefly.
        guard FileManager.default.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // rename(2): replaces an existing file atomically and keeps the temp file's 0600 (replaceItemAt would adopt the old file's mode).
        guard rename(temp.path, file.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
        }
    }
}
