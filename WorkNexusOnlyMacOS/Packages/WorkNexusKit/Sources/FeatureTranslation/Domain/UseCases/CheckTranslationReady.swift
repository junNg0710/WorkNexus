/// Ported from: lib/core/widgets/opencode_not_linked_dialog.dart (`ensureOpenCodeLinked`) + translatesWithApiKeyProvider
import CoreDomain

/// Whether a translation can run: through the user's API key, or through an OpenCode CLI with an authenticated provider.
/// When neither is the case the caller explains how to link OpenCode (`opencode auth login`, or pick an API provider in
/// Settings) instead of letting the translation fail with a raw CLI error.
public struct CheckTranslationReady: Sendable {
    private let apiConfig: TranslationApiConfigRepository
    private let cli: OpenCodeCli

    public init(apiConfig: TranslationApiConfigRepository, cli: OpenCodeCli) { self.apiConfig = apiConfig; self.cli = cli }

    /// A usable API configuration is saved and switched on.
    public func translatesWithApiKey() async -> Bool {
        if case .success(let config?) = await apiConfig.load() { return config.isUsable }
        return false
    }

    public func callAsFunction() async -> Bool {
        if await translatesWithApiKey() { return true }
        return await cli.hasAuthenticatedProvider()
    }
}
