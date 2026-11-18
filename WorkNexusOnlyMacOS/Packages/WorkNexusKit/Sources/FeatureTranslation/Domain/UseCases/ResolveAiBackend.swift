/// Not in the Flutter app: which backend (and model) a purpose runs on, from the saved `AiSetup`.

/// The backend one AI run goes to.
public enum AiBackend: Sendable, Equatable {
    /// The OpenCode CLI; `model` nil leaves OpenCode its configured default.
    case openCode(model: String?)
    /// A saved provider's OpenAI-compatible endpoint, with the config to call it with.
    case api(provider: AiProvider, config: TranslationApiConfig)
}

/// Resolves the effective backend for a purpose. Pure: no I/O.
public struct ResolveAiBackend: Sendable {
    public init() {}

    /// - Parameter callerModel: the model the caller passed (the legacy `AppSettings.translationModel`). It is used for an
    ///   OpenCode choice without a model of its own, but only where the translation choice is in force — AI in chat with
    ///   its own OpenCode choice and no model means OpenCode's default, not the translation's pin.
    public func callAsFunction(_ setup: AiSetup, purpose: AiPurpose, callerModel: String? = nil) -> AiBackend {
        let choice = setup.choice(for: purpose)
        let inheritsTranslation = purpose == .translation || setup.chat == nil
        let ownModel = choice.model.trimmingCharacters(in: .whitespacesAndNewlines)
        // A choice whose provider was removed meanwhile falls back to OpenCode.
        guard !choice.isOpenCode, let provider = setup.provider(choice.providerId) else {
            if !ownModel.isEmpty { return .openCode(model: ownModel) }
            return .openCode(model: inheritsTranslation ? nonEmpty(callerModel) : nil)
        }
        let model = ownModel.isEmpty ? provider.preset.defaultModel : ownModel
        let config = TranslationApiConfig(presetId: provider.presetId, baseUrl: provider.baseUrl.trimmingCharacters(in: .whitespaces),
                                          model: model, apiKey: provider.apiKey.trimmingCharacters(in: .whitespaces))
        return .api(provider: provider, config: config)
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
