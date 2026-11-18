import CoreDomain
import Foundation

/// Gets the bundled MCP server ready for AI tools to run.
/// Ported from: lib/features/chat/domain/repositories/mcp_setup_repository.dart
public protocol McpSetupRepository: Sendable {
    /// Copies the server script out of the app (refreshing an older copy) and looks for Node.js to run it with.
    func prepare() async -> Outcome<McpSetup>
    /// Brings a script copied out earlier up to this build's version; does nothing when the user never set the server up.
    func refreshInstalledScript() async -> Outcome<Void>
}
