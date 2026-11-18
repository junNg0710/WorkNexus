import Foundation

/// What an AI tool needs to run the bundled MCP server: the script, copied out of the app to a fixed place, the Node.js that
/// runs it, and this app's database (the server reads the stored chats from it).
/// Ported from: lib/features/chat/domain/entities/mcp_setup.dart
/// Deviation: `databasePath` is new. The server looks for the Flutter app's database by default, so the native app hands
/// its own through `WORKNEXUS_DB` in every config entry.
public struct McpSetup: Equatable, Sendable {
    public var scriptPath: String
    /// Absolute path of the `node` found on this computer; nil when none.
    public var nodePath: String?
    /// Its `node --version` (`v22.13.0`); nil when none was found.
    public var nodeVersion: String?
    /// The SQLite file the server reads chats from (`WORKNEXUS_DB`).
    public var databasePath: String

    public init(scriptPath: String, nodePath: String? = nil, nodeVersion: String? = nil, databasePath: String) {
        self.scriptPath = scriptPath; self.nodePath = nodePath; self.nodeVersion = nodeVersion; self.databasePath = databasePath
    }

    /// The oldest Node.js the server runs on (it uses the built-in `node:sqlite`).
    public static let minNode = (major: 22, minor: 13)

    /// Whether `nodeVersion` is `minNode` or newer.
    public var nodeSupported: Bool { Self.supports(nodeVersion) }

    /// Whether `nodePath` belongs to one version of a Node.js version manager (nvm, fnm, asdf, mise, nodenv): switching or
    /// removing that version breaks the registered command, so the guide says to register it again.
    public var nodeFromVersionManager: Bool {
        guard let path = nodePath?.replacingOccurrences(of: "\\", with: "/").lowercased() else { return false }
        if Self.versionManagerDirs.contains(where: { path.contains($0) }) { return true }
        // nvm-windows: `.../nvm/v22.13.0/node`.
        guard let r = path.range(of: "/nvm/v") else { return false }
        return path[r.upperBound...].first?.isNumber == true
    }

    private static let versionManagerDirs = ["/.nvm/versions/", "fnm_multishells", "/fnm/node-versions/", "/.asdf/installs/",
                                             "/mise/installs/", "/.nodenv/versions/"]

    /// Whether Node.js `version` (`v22.13.0`) is `minNode` or newer.
    public static func supports(_ version: String?) -> Bool {
        guard var v = version?[...] else { return false }
        if v.hasPrefix("v") { v = v.dropFirst() }
        let majorDigits = v.prefix(while: \.isNumber)
        let rest = v.dropFirst(majorDigits.count)
        guard rest.hasPrefix("."), let major = Int(majorDigits), let minor = Int(rest.dropFirst().prefix(while: \.isNumber)) else { return false }
        return major > minNode.major || (major == minNode.major && minor >= minNode.minor)
    }
}

/// An AI tool the setup guide shows how to register the MCP server with.
public enum McpClient: String, Sendable, CaseIterable { case claudeCode, claudeDesktop, other }

/// How to register the MCP server with one `client`: a command to run, or a JSON entry for `configFile` (nil for a command,
/// or when the file depends on the tool).
/// Ported from: lib/features/chat/domain/value_objects/mcp_client_config.dart
public struct McpClientConfig: Equatable, Sendable {
    public var client: McpClient
    public var configFile: String?
    public var snippet: String
    public init(client: McpClient, configFile: String?, snippet: String) {
        self.client = client; self.configFile = configFile; self.snippet = snippet
    }
}
