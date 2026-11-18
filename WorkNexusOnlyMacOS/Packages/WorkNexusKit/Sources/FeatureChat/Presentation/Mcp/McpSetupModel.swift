import CoreDomain
import Foundation
import Observation

/// The MCP setup guide's state: the bundled server prepared (copied out, Node.js looked for) each time the guide opens, so a
/// Node.js installed meanwhile is found; then the command / config entry for each AI tool.
/// Ported from: lib/features/chat/presentation/providers/mcp_setup_providers.dart
@MainActor @Observable
public final class McpSetupModel {
    public enum State: Equatable {
        case loading
        case ready(McpSetup, [McpClientConfig])
        case failed(String)
    }

    public private(set) var state: State = .loading
    @ObservationIgnored private let repository: McpSetupRepository

    public init(repository: McpSetupRepository) { self.repository = repository }

    /// Prepares the server again (the guide calls it whenever it opens).
    public func load() async {
        state = .loading
        switch await PrepareMcpSetup(repository)() {
        case .success(let setup): state = .ready(setup, BuildMcpClientConfigs()(setup))
        case .failure(let f): state = .failed(f.message)
        }
    }

    /// Whether the guide offers "Get Node.js": a setup is ready and has no Node.js recent enough.
    public var nodeMissing: Bool {
        if case .ready(let setup, _) = state { return !setup.nodeSupported }
        return false
    }

    /// Once per launch: updates the MCP server AI tools were pointed at, when this build bundles a newer one. The failure
    /// (if any) is returned for the host to log.
    public nonisolated static func refreshInstalledScript(_ repository: McpSetupRepository) async -> Failure? {
        await RefreshMcpScript(repository)().failure
    }
}
