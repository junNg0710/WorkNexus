import CoreDomain

/// Ported from: lib/features/translation/domain/repositories/translation_repository.dart
/// Persistent cache of successful translations. Translation *state* is derived by comparing the ticket's current source
/// hash to the stored record's hash — see `ResolveTranslationState`.
public protocol TranslationRepository: Sendable {
    func watchTranslation(ticketId: String) -> AsyncStream<TranslationRecord?>
    func translation(ticketId: String) async -> Outcome<TranslationRecord?>
    func saveTranslation(_ record: TranslationRecord) async -> Outcome<Void>
}

/// Ported from: lib/features/translation/domain/repositories/translation_api_config_repository.dart
public protocol TranslationApiConfigRepository: Sendable {
    /// The saved configuration; nil when none was set up.
    func load() async -> Outcome<TranslationApiConfig?>
    func save(_ config: TranslationApiConfig) async -> Outcome<Void>
    func clear() async -> Outcome<Void>
}

/// Ported from: lib/features/translation/domain/repositories/translation_api_model_catalog.dart
/// The models an OpenAI-compatible endpoint offers, so the user picks one instead of typing a name the provider may have renamed.
public protocol TranslationApiModelCatalog: Sendable {
    /// Model ids served at `baseUrl`, sorted; `apiKey` is empty for endpoints that need none (Ollama).
    func listModels(baseUrl: String, apiKey: String) async -> Outcome<[String]>
}

/// Ported from: lib/features/translation/domain/repositories/opencode_key_repository.dart
/// The API keys the `opencode` CLI translates with — the same store `opencode auth login` maintains.
public protocol OpenCodeKeyRepository: Sendable {
    func authFor(providerId: String) async -> Outcome<OpenCodeProviderAuth>
    /// Stores `key` as `providerId`'s API key, replacing that provider's entry and leaving every other login untouched.
    func saveApiKey(providerId: String, key: String) async -> Outcome<Void>
    /// Deletes `providerId`'s saved API key, leaving every other login (and an OAuth login of this provider) untouched.
    /// Succeeds when there is nothing to remove.
    func removeApiKey(providerId: String) async -> Outcome<Void>
}

/// Ported from: lib/core/domain/adapters/opencode_cli.dart
/// Read-only questions the app asks the locally-installed `opencode` CLI.
public protocol OpenCodeCli: Sendable {
    /// Whether OpenCode has at least one authenticated provider — i.e. whether a headless run has any chance of succeeding.
    func hasAuthenticatedProvider() async -> Bool
    /// The `provider/model` ids the CLI reports. Empty when it can't be asked — callers treat that as "no list", not an error.
    func listModels() async -> [String]
}
