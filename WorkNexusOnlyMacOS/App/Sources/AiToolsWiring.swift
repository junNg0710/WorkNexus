import AppKit
import CoreDomain
import CorePersistence
import CoreUI
import FeatureChat
import Foundation

/// AI tools at the composition root: the loopback chat API the bundled MCP server sends through (run while
/// `AppSettings.chatLocalApi` is on) and the MCP setup guide's model (lib/features/chat/presentation/providers/
/// {chat_local_api_providers,mcp_setup_providers}.dart).
///
/// The MCP server reads chats from this app's database file, so the discovery file `chat_local_api.json` goes beside it and
/// every config entry the guide shows carries its path (`WORKNEXUS_DB`). The demo build (in-memory database, no chat
/// server) runs no API.
@MainActor
final class AiToolsWiring {
    let mcpModel: McpSetupModel
    private let localApi: ChatLocalApiServer?
    private let mcpSetup: McpSetupRepository
    private let handlers: ChatLocalApiHandlers
    private var applied: Bool?
    /// Starts and stops run one after another, in the order the setting changed.
    private var pending: Task<Void, Never>?
    private var terminateObserver: NSObjectProtocol?

    init(db: AppDatabase, repository: ChatRepository, isDemo: Bool) {
        let support = PlatformPaths.applicationSupport()
        let database = db.fileURL
        localApi = isDemo ? nil : database.map { ChatFeature.makeLocalApi(directory: $0.deletingLastPathComponent()) }
        mcpSetup = ChatFeature.makeMcpSetup(
            bundledScript: Bundle.main.url(forResource: "worknexus-mcp", withExtension: "mjs", subdirectory: "Mcp"),
            directory: support.appendingPathComponent("mcp", isDirectory: true),
            databasePath: (database ?? support.appendingPathComponent("worknexus.sqlite")).path)
        mcpModel = McpSetupModel(repository: mcpSetup)
        handlers = .using(repository)
    }

    /// Follows the setting: the API starts when the user turns it on (or at launch when it was left on) and stops when they
    /// turn it off.
    func apply(_ settings: AppSettings) {
        guard let api = localApi, applied != settings.chatLocalApi else { return }
        let on = settings.chatLocalApi, handlers = handlers, previous = pending
        applied = on
        pending = Task {
            await previous?.value
            let result = on ? await api.start(handlers) : await api.stop()
            // Only the failure's own text: requests and their contents are never logged.
            if case .failure(let f) = result { Diagnostics.error("chat", "Local chat API: \(f.message)") }
        }
    }

    /// Once per launch: keeps a server copied out earlier in step with this build, and removes the discovery file when the
    /// app quits.
    func start() {
        let setup = mcpSetup
        Task.detached(priority: .utility) {
            // A build without the bundled server (`.notFound`) has nothing to update.
            guard let f = await McpSetupModel.refreshInstalledScript(setup) else { return }
            if case .notFound = f { return }
            Diagnostics.error("chat", "MCP server update: \(f.message)")
        }
        guard let api = localApi else { return }
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                                                   queue: nil) { _ in api.removeDiscoveryFileNow() }
    }
}
