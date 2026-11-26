import CoreDomain
import CorePersistence
import Foundation

/// Public entry point of FeatureTranslation: wires the backends and repositories once. The composition root keeps one
/// instance and hands `service` / `repository` to whoever translates (ticket detail, chat), and the setup / key / catalog
/// repositories to the settings UI.
public struct TranslationFeature: Sendable {
    public let service: TranslationService
    public let repository: TranslationRepository
    /// Every saved AI provider and the provider + model per purpose (macOS only; replaces the single API config).
    public let aiSetup: AiSetupRepository
    public let openCodeKeys: OpenCodeKeyRepository
    public let modelCatalog: TranslationApiModelCatalog
    public let openCodeCli: OpenCodeCli
    public let claudeCodeCli: ClaudeCodeCli
    public let resolveState = ResolveTranslationState()
    /// Translates a ticket's comments and history notes (see `TranslateTicketNotes`).
    public var translateNotes: TranslateTicketNotes { TranslateTicketNotes(service: service, repository: repository) }

    public init(service: TranslationService, repository: TranslationRepository, aiSetup: AiSetupRepository,
                openCodeKeys: OpenCodeKeyRepository, modelCatalog: TranslationApiModelCatalog, openCodeCli: OpenCodeCli,
                claudeCodeCli: ClaudeCodeCli = ClaudeCodeCliRunner()) {
        self.service = service; self.repository = repository; self.aiSetup = aiSetup; self.openCodeKeys = openCodeKeys
        self.modelCatalog = modelCatalog; self.openCodeCli = openCodeCli; self.claudeCodeCli = claudeCodeCli
    }

    /// The production wiring: the API backend (keys from `credentials`) and the OpenCode CLI, routed per purpose by the
    /// saved setup; cache in `database`.
    public static func make(database: AppDatabase, credentials: CredentialStore, http: TranslationHTTPClient = URLSessionTranslationClient(),
                            cli: CliRunner = CliRunner()) -> TranslationFeature {
        let aiSetup = CredentialAiSetupRepository(store: credentials)
        let service = RoutingTranslationService(api: ApiTranslationService(http: http), openCode: OpenCodeTranslationService(runner: cli),
                                                claudeCode: ClaudeCodeTranslationService(runner: cli), setup: { await aiSetup.load().value ?? .empty })
        return TranslationFeature(service: service, repository: GRDBTranslationRepository(database: database), aiSetup: aiSetup,
                                  openCodeKeys: OpenCodeAuthFileKeyRepository(), modelCatalog: OpenAIModelCatalogDataSource(http: http),
                                  openCodeCli: OpenCodeCliRunner(runner: cli), claudeCodeCli: ClaudeCodeCliRunner(runner: cli))
    }
}
