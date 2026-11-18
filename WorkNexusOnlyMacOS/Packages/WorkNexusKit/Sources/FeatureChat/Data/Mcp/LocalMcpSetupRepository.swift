import CoreDomain
import Foundation

/// `McpSetupRepository` over the bundled script and this computer's Node.js.
/// Ported from: lib/features/chat/data/repositories/local_mcp_setup_repository.dart
struct LocalMcpSetupRepository: McpSetupRepository {
    let installer: McpScriptInstaller
    let probe: NodeRuntimeProbe
    /// The database the server reads (`WORKNEXUS_DB`).
    let databasePath: String

    func prepare() async -> Outcome<McpSetup> {
        let script: String
        do { script = try installer.install() } catch McpScriptInstaller.InstallError.notBundled {
            return .failure(.notFound("This build has no MCP server"))
        } catch {
            return .failure(.storage("Could not copy the MCP server"))
        }
        let nodes = await probe.findAll()
        // The first one recent enough, even if an older one comes first in PATH.
        let node = nodes.first { McpSetup.supports($0.version) } ?? nodes.first
        return .success(McpSetup(scriptPath: script, nodePath: node?.path, nodeVersion: node?.version, databasePath: databasePath))
    }

    func refreshInstalledScript() async -> Outcome<Void> {
        do { _ = try installer.refresh(); return .success(()) } catch McpScriptInstaller.InstallError.notBundled {
            return .failure(.notFound("This build has no MCP server"))
        } catch {
            return .failure(.storage("Could not update the MCP server"))
        }
    }
}
