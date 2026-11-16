import CoreDomain
import CorePersistence
import Foundation

/// Public entry point of FeatureTranslation: wires the backends and repositories once. The composition root keeps one
/// instance and hands `service` / `repository` to whoever translates (ticket detail, chat), and the config / key /
/// catalog repositories to the settings UI.
public struct TranslationFeature: Sendable {
    public let service: TranslationService
    public let repository: TranslationRepository
    public let apiConfig: TranslationApiConfigRepository
    public let openCodeKeys: OpenCodeKeyRepository
    public let modelCatalog: TranslationApiModelCatalog
    public let openCodeCli: OpenCodeCli
    public let resolveState = ResolveTranslationState()

    public init(service: TranslationService, repository: TranslationRepository, apiConfig: TranslationApiConfigRepository,
                openCodeKeys: OpenCodeKeyRepository, modelCatalog: TranslationApiModelCatalog, openCodeCli: OpenCodeCli) {
        self.service = service; self.repository = repository; self.apiConfig = apiConfig; self.openCodeKeys = openCodeKeys
        self.modelCatalog = modelCatalog; self.openCodeCli = openCodeCli
    }

    /// The production wiring: API backend (key from `credentials`) routed against the OpenCode CLI, cache in `database`.
    public static func make(database: AppDatabase, credentials: CredentialStore, http: TranslationHTTPClient = URLSessionTranslationClient(),
                            cli: CliRunner = CliRunner()) -> TranslationFeature {
        let apiConfig = CredentialTranslationApiConfigRepository(store: credentials)
        let configProvider: @Sendable () async -> TranslationApiConfig? = { await apiConfig.load().value ?? nil }
        let service = RoutingTranslationService(api: ApiTranslationService(http: http, config: configProvider),
                                                openCode: OpenCodeTranslationService(runner: cli), config: configProvider)
        return TranslationFeature(service: service, repository: GRDBTranslationRepository(database: database), apiConfig: apiConfig,
                                  openCodeKeys: OpenCodeAuthFileKeyRepository(), modelCatalog: OpenAIModelCatalogDataSource(http: http),
                                  openCodeCli: OpenCodeCliRunner(runner: cli))
    }
}
