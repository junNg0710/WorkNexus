/// Ported from: lib/core/widgets/opencode_not_linked_dialog.dart (`ensureOpenCodeLinked`) + translatesWithApiKeyProvider
/// (per purpose and over several providers: not in the Flutter app)
import CoreDomain

/// Whether an AI run for a purpose can start: its provider is usable (a key, or one that needs none), or it runs on an
/// OpenCode CLI with an authenticated provider. When it cannot, the caller explains how to set one up (`opencode auth
/// login`, or pick an API provider in Settings) instead of letting the run fail with a raw CLI error.
public struct CheckTranslationReady: Sendable {
    private let setup: AiSetupRepository
    private let cli: OpenCodeCli

    public init(setup: AiSetupRepository, cli: OpenCodeCli) { self.setup = setup; self.cli = cli }

    /// The backend `purpose` resolves to; OpenCode when the setup cannot be read.
    public func backend(_ purpose: AiPurpose) async -> AiBackend {
        ResolveAiBackend()(await setup.load().value ?? .empty, purpose: purpose)
    }

    /// `purpose` runs on a saved provider (not OpenCode).
    public func usesApiProvider(_ purpose: AiPurpose = .translation) async -> Bool {
        if case .api = await backend(purpose) { return true }
        return false
    }

    /// Why `purpose` cannot run yet, or `.ready`.
    public func readiness(_ purpose: AiPurpose = .translation) async -> AiReadiness {
        switch await backend(purpose) {
        case .api(let provider, let config):
            provider.isUsable && !config.model.isEmpty ? .ready : .providerNotUsable(name: provider.name)
        case .openCode:
            await cli.hasAuthenticatedProvider() ? .ready : .openCodeNotLinked
        }
    }

    public func callAsFunction(_ purpose: AiPurpose = .translation) async -> Bool { await readiness(purpose) == .ready }
}

/// Whether an AI run can start, and what to tell the user when it cannot.
public enum AiReadiness: Sendable, Equatable {
    case ready
    /// The run would go to OpenCode, which has no authenticated provider.
    case openCodeNotLinked
    /// The run would go to a saved provider that lacks its key, endpoint or model.
    case providerNotUsable(name: String)
}
