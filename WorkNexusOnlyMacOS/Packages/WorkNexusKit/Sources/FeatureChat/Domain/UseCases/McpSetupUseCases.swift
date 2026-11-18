import CoreDomain
import Foundation

/// Gets the bundled MCP server ready to register with an AI tool.
/// Ported from: lib/features/chat/domain/usecases/prepare_mcp_setup.dart
public struct PrepareMcpSetup: Sendable {
    private let repository: McpSetupRepository
    public init(_ repository: McpSetupRepository) { self.repository = repository }
    public func callAsFunction() async -> Outcome<McpSetup> { await repository.prepare() }
}

/// Keeps the MCP server AI tools were pointed at in step with this app: the copy is only refreshed when the setup guide is
/// opened, so without this an app update would leave registered tools on the old server (missing new tools, or reading a
/// database it no longer understands).
/// Ported from: lib/features/chat/domain/usecases/refresh_mcp_script.dart
public struct RefreshMcpScript: Sendable {
    private let repository: McpSetupRepository
    public init(_ repository: McpSetupRepository) { self.repository = repository }
    public func callAsFunction() async -> Outcome<Void> { await repository.refreshInstalledScript() }
}

/// The ways to register the bundled MCP server with AI tools on macOS: the Claude Code command, the Claude Desktop config
/// entry, and the same entry for any other MCP client. All use absolute paths: a GUI-launched tool does not get the user's
/// shell `PATH`, so a bare `node` may not be found.
/// Ported from: lib/features/chat/domain/usecases/build_mcp_client_configs.dart
/// Deviations: macOS only (this app has no other build); every entry carries `WORKNEXUS_DB`, the native app's database —
/// without it the server would read the Flutter app's (`com.worknexus.workNexus`); the command's paths are single-quoted
/// for the shell.
public struct BuildMcpClientConfigs: Sendable {
    /// The name the server is registered under.
    public static let serverName = "worknexus"
    /// The variable that tells the server where this app's database is.
    public static let databaseVariable = "WORKNEXUS_DB"
    public static let claudeDesktopConfig = "~/Library/Application Support/Claude/claude_desktop_config.json"

    public init() {}

    public func callAsFunction(_ setup: McpSetup) -> [McpClientConfig] {
        let node = setup.nodePath ?? "node"
        let command = "claude mcp add \(Self.serverName) -s user -e \(Self.databaseVariable)=\(Self.shellQuoted(setup.databasePath)) -- "
            + "\(Self.shellQuoted(node)) \(Self.shellQuoted(setup.scriptPath))"
        let entry = """
        {
          "mcpServers": {
            "\(Self.serverName)": {
              "command": \(Self.jsonString(node)),
              "args": [
                \(Self.jsonString(setup.scriptPath))
              ],
              "env": {
                "\(Self.databaseVariable)": \(Self.jsonString(setup.databasePath))
              }
            }
          }
        }
        """
        return [
            McpClientConfig(client: .claudeCode, configFile: nil, snippet: command),
            McpClientConfig(client: .claudeDesktop, configFile: Self.claudeDesktopConfig, snippet: entry),
            McpClientConfig(client: .other, configFile: nil, snippet: entry),
        ]
    }

    /// `value` as one shell word: single-quoted, with any `'` closed, escaped and reopened.
    static func shellQuoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }

    /// `value` as a JSON string literal (quotes, backslashes and control characters escaped; slashes kept).
    static func jsonString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "\"\""
    }
}
